import { describe, expect, it, vi } from "vitest";
import type { InboxPhotoDraft } from "./inbox-photo";
import {
  synchronizeCapturePhotos,
  type CapturePhotoOperations,
} from "./inbox-photo-sync";
import type { QueuedInboxEntry } from "./inbox-queue";
import type { InboxSyncResult } from "./inbox-sync";
import type { StorageFailure } from "./sync-failure";

const ownerId = "10000000-0000-4000-8000-000000000003";
const entryId = "10000000-0000-4000-8000-000000000001";
const firstId = "10000000-0000-4000-8000-000000000002";
const secondId = "10000000-0000-4000-8000-000000000004";
const firstPath = `${ownerId}/${entryId}/${firstId}.jpg`;

const attached: InboxSyncResult = {
  message: "Photo attached.",
  status: "synced",
};
const offline: InboxSyncResult = {
  message:
    "Photos are saved on this device. MemoTrail will retry when you are online.",
  status: "retry",
};
const signIn: InboxSyncResult = {
  message: "Your session expired. Sign in again to sync this Entry's photos.",
  status: "retry",
};
const refused: InboxSyncResult = {
  message:
    "This Entry is in your Library, but MemoTrail cannot accept one of its photos, so they will not sync. Discard to remove them from this device.",
  status: "rejected",
};
const trashed: InboxSyncResult = {
  message:
    "This Entry is in Trash, so its photos will not be attached. Discard to remove them from this device.",
  status: "rejected",
};

// Storage answers most refusals with HTTP 400 and the real status in its body.
const storageError = (statusCode: string): StorageFailure => ({
  status: 400,
  statusCode,
});

describe("Capture photo synchronization", () => {
  it("uploads, registers, and clears each photo in order", async () => {
    const { operations, progress } = setup();

    expect(
      await synchronizeCapturePhotos(
        ownerId,
        capture(firstId, secondId),
        operations,
        (step) => progress.push(step),
      ),
    ).toEqual({ message: "Saved to Library with 2 photos.", status: "synced" });
    expect(operations.upload).toHaveBeenCalledTimes(2);
    expect(operations.upload).toHaveBeenNthCalledWith(
      1,
      firstPath,
      expect.objectContaining({ id: firstId }),
    );
    expect(operations.register).toHaveBeenCalledWith(
      expect.objectContaining({ attachmentId: firstId, objectPath: firstPath }),
      { originalOnDevice: true },
    );
    expect(operations.removePhoto).toHaveBeenCalledWith(firstId);
    expect(operations.removePhoto).toHaveBeenCalledWith(secondId);
    expect(progress).toEqual([
      { completed: 0, total: 2 },
      { completed: 1, total: 2 },
      { completed: 2, total: 2 },
    ]);
  });

  it("registers an original an earlier attempt already stored", async () => {
    // The earlier upload's response was lost, so this one finds it in place.
    const { operations } = setup({ upload: { error: storageError("409") } });

    expect(
      await synchronizeCapturePhotos(ownerId, capture(firstId), operations),
    ).toMatchObject({ status: "synced" });
    expect(operations.register).toHaveBeenCalledOnce();
    expect(operations.sessionFailure).not.toHaveBeenCalled();
  });

  it.each([
    [
      "413",
      "This Entry is in your Library, but one of its photos is too large for MemoTrail, so they will not sync. Discard to remove them from this device.",
    ],
    [
      "415",
      "This Entry is in your Library, but one of its photos is a file type MemoTrail does not accept, so they will not sync. Discard to remove them from this device.",
    ],
    [
      "400",
      "This Entry is in your Library, but MemoTrail cannot accept one of its photos, so they will not sync. Discard to remove them from this device.",
    ],
  ])(
    "stops a photo Storage refuses with %s and never registers it",
    async (statusCode, message) => {
      const { operations } = setup({
        upload: { error: storageError(statusCode) },
      });

      expect(
        await synchronizeCapturePhotos(
          ownerId,
          capture(firstId, secondId),
          operations,
        ),
      ).toEqual({ message, status: "rejected" });
      expect(operations.upload).toHaveBeenCalledOnce();
      expect(operations.register).not.toHaveBeenCalled();
      expect(operations.removePhoto).not.toHaveBeenCalled();
    },
  );

  it.each([
    ["no response", {}],
    ["rate limiting", storageError("429")],
    ["a server error", storageError("503")],
    ["a gateway error page", { status: 502, statusCode: "502" }],
  ])("keeps a photo waiting after %s", async (_, error) => {
    const { operations } = setup({ upload: { error } });

    expect(
      await synchronizeCapturePhotos(ownerId, capture(firstId), operations),
    ).toEqual(offline);
    expect(operations.register).not.toHaveBeenCalled();
    expect(operations.removePhoto).not.toHaveBeenCalled();
  });

  it("checks the session before treating a denied upload as a refusal", async () => {
    // Storage reports an expired session exactly like a policy denial.
    const denied = { upload: { error: storageError("403") } };

    let { operations } = setup({ ...denied, session: "session" });
    expect(
      await synchronizeCapturePhotos(ownerId, capture(firstId), operations),
    ).toEqual(signIn);

    ({ operations } = setup({ ...denied, session: "unavailable" }));
    expect(
      await synchronizeCapturePhotos(ownerId, capture(firstId), operations),
    ).toEqual(offline);

    ({ operations } = setup({ ...denied, session: null }));
    expect(
      await synchronizeCapturePhotos(ownerId, capture(firstId), operations),
    ).toEqual(refused);
    expect(operations.register).not.toHaveBeenCalled();
  });

  it("asks for a new sign-in when Storage reports one", async () => {
    const { operations } = setup({ upload: { error: storageError("401") } });

    expect(
      await synchronizeCapturePhotos(ownerId, capture(firstId), operations),
    ).toEqual(signIn);
    expect(operations.sessionFailure).not.toHaveBeenCalled();
  });

  it("clears an upload MemoTrail refused to register", async () => {
    // The Entry went to Trash while the photo was on its way.
    const { operations } = setup({ register: trashed });

    expect(
      await synchronizeCapturePhotos(ownerId, capture(firstId), operations),
    ).toEqual(trashed);
    expect(operations.removeUpload).toHaveBeenCalledWith(firstPath);
    expect(operations.removePhoto).not.toHaveBeenCalled();
  });

  it("keeps the refusal when its upload cannot be cleared", async () => {
    const { operations } = setup({ register: trashed });
    operations.removeUpload.mockRejectedValue(new Error("offline"));

    expect(
      await synchronizeCapturePhotos(ownerId, capture(firstId), operations),
    ).toEqual(trashed);
  });

  it("keeps a stored original for a registration that may still succeed", async () => {
    const waiting: InboxSyncResult = {
      message:
        "The photo is saved on this device. MemoTrail will retry attaching it.",
      status: "retry",
    };
    const { operations } = setup({ register: waiting });

    expect(
      await synchronizeCapturePhotos(ownerId, capture(firstId), operations),
    ).toEqual(waiting);
    expect(operations.removeUpload).not.toHaveBeenCalled();
  });

  it("registers a photo this device no longer has without uploading it", async () => {
    const { operations, progress } = setup({ photos: [] });

    expect(
      await synchronizeCapturePhotos(
        ownerId,
        capture(firstId),
        operations,
        (step) => progress.push(step),
      ),
    ).toMatchObject({ status: "synced" });
    expect(operations.upload).not.toHaveBeenCalled();
    expect(operations.register).toHaveBeenCalledWith(
      expect.objectContaining({ attachmentId: firstId }),
      { originalOnDevice: false },
    );
    expect(progress).toEqual([
      { completed: 0, total: 1 },
      { completed: 1, total: 1 },
    ]);
  });

  it("passes on why a photo this device no longer has cannot be registered", async () => {
    const missing: InboxSyncResult = {
      message:
        "This Entry is in your Library, but one of its photos is no longer on this device, so they will not sync. Discard to remove them from this device.",
      status: "rejected",
    };
    const { operations } = setup({ photos: [], register: missing });

    expect(
      await synchronizeCapturePhotos(ownerId, capture(firstId), operations),
    ).toEqual(missing);
  });

  it("refuses a photo that changed on this device before uploading it", async () => {
    const { operations } = setup({
      photos: [photo(firstId, { name: "renamed.jpg" })],
    });

    expect(
      await synchronizeCapturePhotos(ownerId, capture(firstId), operations),
    ).toMatchObject({ status: "rejected" });
    expect(operations.upload).not.toHaveBeenCalled();
  });

  it("finishes later when this device cannot clear its copy", async () => {
    const { operations } = setup();
    operations.removePhoto.mockRejectedValue(new Error("blocked"));

    expect(
      await synchronizeCapturePhotos(ownerId, capture(firstId), operations),
    ).toEqual({
      message:
        "This photo reached MemoTrail, but its local pending copy could not be cleared. Retry to finish.",
      status: "retry",
    });
  });
});

function capture(...attachmentIds: string[]): QueuedInboxEntry {
  return {
    attachments: attachmentIds.map((id) => ({
      id,
      lastModified: 1,
      mimeType: "image/jpeg",
      name: `${id}.jpg`,
      size: 3,
    })),
    body: "A thought worth keeping.",
    id: entryId,
    occurredAt: "2026-10-03T12:00:00.000Z",
    occurredTimezone: "UTC",
    queuedAt: "2026-10-03T12:00:00.000Z",
    title: null,
    version: 2,
  };
}

function photo(
  id: string,
  { name = `${id}.jpg` }: { name?: string } = {},
): InboxPhotoDraft {
  return {
    file: new File(["abc"], name, { lastModified: 1, type: "image/jpeg" }),
    id,
    mimeType: "image/jpeg",
  };
}

function setup({
  photos = [photo(firstId), photo(secondId)],
  register = attached,
  session = null,
  upload = { error: null },
}: {
  photos?: InboxPhotoDraft[];
  register?: InboxSyncResult;
  session?: "session" | "unavailable" | null;
  upload?: { error: StorageFailure | null };
} = {}) {
  const operations = {
    loadPhotos: vi.fn(async () => photos),
    register: vi.fn(async () => register),
    removePhoto: vi.fn(async () => undefined),
    removeUpload: vi.fn(async () => undefined),
    sessionFailure: vi.fn(async () => session),
    upload: vi.fn(async () => upload),
  } satisfies CapturePhotoOperations;
  return { operations, progress: [] as unknown[] };
}
