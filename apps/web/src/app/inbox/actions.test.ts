import { beforeEach, describe, expect, it, vi } from "vitest";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import type { QueuedInboxEntry } from "@/lib/data/inbox-queue";
import { registerEntryAttachment, syncInboxEntry } from "./actions";

vi.mock("server-only", () => ({}));
vi.mock("next/cache", () => ({ revalidatePath: vi.fn() }));
vi.mock("next/server", () => ({ after: vi.fn() }));
vi.mock("@/lib/data/inbox", () => ({ getAuthenticatedContext: vi.fn() }));
vi.mock("@/lib/ai/suggestions-server", () => ({ suggestForEntry: vi.fn() }));
vi.mock("@/lib/search/search-index", () => ({
  scheduleSearchIndexDrain: vi.fn(),
}));

const owner = "10000000-0000-4000-8000-000000000003";
const entryId = "10000000-0000-4000-8000-000000000001";
const attachmentId = "10000000-0000-4000-8000-000000000002";
const offline = {
  message: "Saved on this device. MemoTrail will retry when you are online.",
  status: "retry",
};
const signIn = {
  message: "Your session expired. Sign in again to sync this Entry.",
  status: "retry",
};
const rejectedEntry = {
  message:
    "MemoTrail cannot accept this Entry, so it will not sync. Copy its text to keep it, then discard it.",
  status: "rejected",
};
const deletedForever = {
  message:
    "This Entry was deleted forever, so MemoTrail will not create it again. Copy its text to keep it, then discard it.",
  status: "rejected",
};
const trashedPhoto = {
  message:
    "This Entry is in Trash, so its photos will not be attached. Discard to remove them from this device.",
  status: "rejected",
};

describe("Capture sync failures", () => {
  beforeEach(() => vi.resetAllMocks());

  it("syncs a capture MemoTrail accepts", async () => {
    const { insert } = signedIn({ insert: { error: null, status: 201 } });
    expect(await syncInboxEntry(capture())).toEqual({
      message: "Saved to Library.",
      status: "synced",
    });
    expect(insert).toHaveBeenCalledOnce();
  });

  it("rejects a capture Postgres can never store instead of calling it offline", async () => {
    signedIn({
      insert: {
        error: {
          code: "22P05",
          message: "unsupported Unicode escape sequence",
        },
        status: 400,
      },
    });
    expect(await syncInboxEntry(capture("A NUL \u0000 character"))).toEqual(
      rejectedEntry,
    );
  });

  it.each([
    ["23514", 400],
    ["23505", 409],
    ["42501", 403],
    ["PGRST102", 400],
  ])(
    "rejects %s when the Entry does not already exist",
    async (code, status) => {
      signedIn({ insert: { error: { code, message: "refused" }, status } });
      expect(await syncInboxEntry(capture())).toEqual(rejectedEntry);
    },
  );

  it("counts an Entry that already reached MemoTrail as synced, whatever the error", async () => {
    signedIn({
      existing: { deleted_at: null, id: entryId },
      insert: { error: { code: "23505", message: "duplicate" }, status: 409 },
    });
    expect(await syncInboxEntry(capture())).toMatchObject({
      status: "synced",
    });
  });

  it("stops a capture whose Entry is already in Trash", async () => {
    // Sending it again would only repeat the duplicate-key refusal forever.
    const trashed = {
      existing: { deleted_at: "2026-10-03T12:05:00.000Z", id: entryId },
      insert: { error: { code: "23505", message: "duplicate" }, status: 409 },
    };
    signedIn(trashed);
    expect(await syncInboxEntry(capture())).toEqual({
      message:
        "This Entry is already in Trash, so it will not sync again. Restore it from Trash to keep it, then discard this copy.",
      status: "rejected",
    });

    signedIn(trashed);
    expect(await syncInboxEntry(captureWithPhoto())).toEqual(trashedPhoto);
  });

  it("never recreates an Entry that was deleted forever", async () => {
    const { lookup } = signedIn({
      insert: {
        error: { code: "23505", message: "entry_deleted_forever" },
        status: 409,
      },
    });
    expect(await syncInboxEntry(capture())).toEqual(deletedForever);
    expect(lookup).not.toHaveBeenCalled();
  });

  it("keeps a refusal retryable when MemoTrail cannot say whether the Entry exists", async () => {
    // An earlier attempt may have created it before its response was lost.
    signedIn({
      insert: { error: { code: "23505", message: "duplicate" }, status: 409 },
      lookupError: { code: "", message: "fetch failed" },
    });
    expect(await syncInboxEntry(capture())).toEqual(offline);

    signedIn({
      insert: {
        error: { code: "PGRST303", message: "JWT expired" },
        status: 401,
      },
      lookupError: { code: "PGRST303", message: "JWT expired" },
    });
    expect(await syncInboxEntry(capture())).toEqual(signIn);
  });

  it.each([
    ["", 0],
    ["PGRST003", 504],
    ["40001", 409],
    ["57014", 500],
  ])("keeps %s retryable with the offline message", async (code, status) => {
    signedIn({ insert: { error: { code, message: "unavailable" }, status } });
    expect(await syncInboxEntry(capture())).toEqual(offline);
  });

  it("asks the person to sign in again when the session is gone or expires", async () => {
    vi.mocked(getAuthenticatedContext).mockResolvedValue(null);
    expect(await syncInboxEntry(capture())).toEqual(signIn);

    signedIn({
      insert: {
        error: { code: "PGRST303", message: "JWT expired" },
        status: 401,
      },
    });
    expect(await syncInboxEntry(capture())).toEqual(signIn);
  });

  it("rejects a capture whose stored copy is invalid before reaching MemoTrail", async () => {
    const invalid = {
      message:
        "This Entry is invalid on this device, so it will not sync. Copy its text to keep it, then discard it.",
      status: "rejected",
    };
    expect(await syncInboxEntry({ ...capture(), id: "not-a-uuid" })).toEqual(
      invalid,
    );
    expect(await syncInboxEntry(capture(), "{")).toEqual(invalid);
    expect(getAuthenticatedContext).not.toHaveBeenCalled();
  });
});

describe("Capture photo sync failures", () => {
  beforeEach(() => vi.resetAllMocks());
  const rejectedPhoto = {
    message:
      "This Entry is in your Library, but MemoTrail cannot accept one of its photos, so they will not sync. Discard to remove them from this device.",
    status: "rejected",
  };
  const waitingPhoto = {
    message:
      "The photo is saved on this device. MemoTrail will retry attaching it.",
    status: "retry",
  };

  it("attaches a registered photo", async () => {
    signedIn({ rpc: { data: [{ attachment_id: attachmentId }], error: null } });
    expect(await registerEntryAttachment(photo())).toEqual({
      message: "Photo attached.",
      status: "synced",
    });
  });

  it.each([
    ["23505", "attachment_conflict", 409],
    ["22023", "invalid_attachment_metadata", 400],
  ])("rejects %s %s", async (code, message, status) => {
    signedIn({ rpc: { data: null, error: { code, message }, status } });
    expect(await registerEntryAttachment(photo())).toEqual(rejectedPhoto);
  });

  it("keeps waiting for an original that has not reached Storage yet", async () => {
    signedIn({
      rpc: {
        data: null,
        error: { code: "22023", message: "attachment_object_missing" },
        status: 400,
      },
    });
    expect(await registerEntryAttachment(photo())).toEqual(waitingPhoto);
  });

  it("refuses an original that never reached Storage once this device lost it", async () => {
    signedIn({
      rpc: {
        data: null,
        error: { code: "22023", message: "attachment_object_missing" },
        status: 400,
      },
    });
    expect(
      await registerEntryAttachment(photo(), { originalOnDevice: false }),
    ).toEqual({
      message:
        "This Entry is in your Library, but one of its photos is no longer on this device, so they will not sync. Discard to remove them from this device.",
      status: "rejected",
    });
  });

  it("keeps waiting when MemoTrail cannot be reached or confirms nothing", async () => {
    signedIn({
      rpc: {
        data: null,
        error: { code: "", message: "fetch failed" },
        status: 0,
      },
    });
    expect(await registerEntryAttachment(photo())).toEqual(waitingPhoto);

    signedIn({ rpc: { data: [], error: null, status: 200 } });
    expect(await registerEntryAttachment(photo())).toEqual(waitingPhoto);

    // A registration this device can still repeat, even without the photo.
    signedIn({ rpc: { data: [], error: null, status: 200 } });
    expect(
      await registerEntryAttachment(photo(), { originalOnDevice: false }),
    ).toEqual({
      message:
        "MemoTrail will retry attaching this Entry's photos when you are online.",
      status: "retry",
    });
  });

  it("stops attaching photos to an Entry in Trash or deleted forever", async () => {
    signedIn({
      rpc: {
        data: null,
        error: { code: "22023", message: "entry_in_trash" },
        status: 400,
      },
    });
    expect(await registerEntryAttachment(photo())).toEqual(trashedPhoto);

    signedIn({
      rpc: {
        data: null,
        error: { code: "23505", message: "entry_deleted_forever" },
        status: 409,
      },
    });
    expect(await registerEntryAttachment(photo())).toEqual(deletedForever);
  });

  it("asks the person to sign in again without a session", async () => {
    vi.mocked(getAuthenticatedContext).mockResolvedValue(null);
    expect(await registerEntryAttachment(photo())).toEqual({
      message:
        "Your session expired. Sign in again to sync this Entry's photos.",
      status: "retry",
    });
  });

  it("rejects a photo reference that can never be registered", async () => {
    expect(
      await registerEntryAttachment({
        ...photo(),
        mimeType: "image/gif" as never,
      }),
    ).toEqual(rejectedPhoto);
    expect(getAuthenticatedContext).not.toHaveBeenCalled();
  });
});

function capture(body = "A thought worth keeping."): QueuedInboxEntry {
  return {
    attachments: [],
    body,
    id: entryId,
    occurredAt: "2026-10-03T12:00:00.000Z",
    occurredTimezone: "UTC",
    queuedAt: "2026-10-03T12:00:00.000Z",
    title: null,
    version: 2,
  };
}

function captureWithPhoto(): QueuedInboxEntry {
  return {
    ...capture(),
    attachments: [
      {
        id: attachmentId,
        lastModified: 1,
        mimeType: "image/jpeg",
        name: "memory.jpg",
        size: 10,
      },
    ],
  };
}

function photo() {
  return {
    attachmentId,
    byteSize: 10,
    entryId,
    mimeType: "image/jpeg" as const,
    objectPath: `${owner}/${entryId}/${attachmentId}.jpg`,
    originalFilename: "memory.jpg",
    pixelHeight: null,
    pixelWidth: null,
  };
}

function signedIn({
  existing = null,
  insert: insertResult = { error: null, status: 201 },
  lookupError = null,
  rpc: rpcResult = { data: [], error: null },
}: {
  existing?: { deleted_at: string | null; id: string } | null;
  insert?: { error: { code: string; message: string } | null; status: number };
  lookupError?: { code: string; message: string } | null;
  rpc?: {
    data: unknown;
    error: { code: string; message: string } | null;
    status?: number;
  };
}) {
  const insert = vi.fn(async () => insertResult);
  const lookup = vi.fn(async () => ({
    data: lookupError ? null : existing,
    error: lookupError,
  }));
  const query = {
    eq: () => query,
    maybeSingle: lookup,
    select: () => query,
  };
  const rpc = vi.fn(async () => rpcResult);
  vi.mocked(getAuthenticatedContext).mockResolvedValue({
    client: { from: () => ({ insert, ...query }), rpc },
    userId: owner,
  } as unknown as NonNullable<
    Awaited<ReturnType<typeof getAuthenticatedContext>>
  >);
  return { insert, lookup, rpc };
}
