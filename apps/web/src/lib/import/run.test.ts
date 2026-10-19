import { describe, expect, it } from "vitest";
import { plainTextDocument } from "@/lib/data/rich-text";
import { importEntryId } from "./identity";
import { defaultImportOptions } from "./tags";
import {
  ImportItemError,
  ImportLeaseLost,
  ImportQuotaError,
  buildEntryArgs,
  runImport,
  sniffImageMime,
  type ClaimedItem,
  type ImportEntryArgs,
  type ImportEntryOutcome,
  type ImportGateway,
} from "./run";
import type { ImportPayload } from "./scan";
import type { ImportItemMedia } from "./types";
import { tinyJpeg, tinyPng } from "./test-zip";

const ownerId = "11111111-1111-4111-8111-111111111111";
const options = defaultImportOptions("America/New_York", {
  distinctParentFolders: 0,
  notionDateProperty: null,
});

function payload(overrides: Partial<ImportPayload> = {}): ImportPayload {
  return {
    bodyRich: plainTextDocument("Hello from the source."),
    date: { local: "2024-05-12", precision: "day" },
    fileModifiedAt: null,
    folderPath: [],
    locationLabel: null,
    propertyTagNames: [],
    skippedResources: [],
    source: "markdown",
    sourceCreatedAt: null,
    sourceKey: "a.md",
    sourceModifiedAt: null,
    tagNames: ["travel"],
    title: "Lisbon",
    warnings: [],
    ...overrides,
  } as ImportPayload;
}

function item(
  index: number,
  overrides: Partial<ClaimedItem> = {},
  media: ImportItemMedia | null = null,
): ClaimedItem {
  return {
    contentHash: `hash-${index}`,
    entryId: null,
    itemId: `item-${index}`,
    media,
    payload: payload({ sourceKey: `n${index}.md` }),
    sourceKey: `n${index}.md`,
    status: "pending",
    ...overrides,
  };
}

function photo(key: string): ImportItemMedia["photos"][number] {
  return {
    byteSize: 10,
    key,
    originalFilename: `${key}.png`,
    status: "pending",
    zipPath: `${key}.png`,
  };
}

type Finished = {
  itemId: string;
  status: string;
  reason: string | null;
  retryable: boolean;
  media: ImportItemMedia | null;
};

function fakeGateway(
  batches: ClaimedItem[][],
  behavior: {
    outcome?: (args: ImportEntryArgs) => ImportEntryOutcome;
    importError?: (args: ImportEntryArgs) => Error | null;
    upload?: (path: string, attempt: number) => Error | null;
    register?: () => Error | null;
    lease?: boolean;
    finishJobStatus?: string;
  } = {},
) {
  const log = {
    finished: [] as Finished[],
    imported: [] as ImportEntryArgs[],
    paused: 0,
    released: 0,
    registered: [] as string[],
    uploads: [] as string[],
    finishJobs: 0,
  };
  const attempts = new Map<string, number>();
  const queue = [...batches];
  const gateway: ImportGateway = {
    acquireLease: async () => (behavior.lease === false ? null : "token"),
    claim: async () => queue.shift() ?? [],
    finishItem: async (itemId, status, reason, retryable, media) => {
      log.finished.push({ itemId, media, reason, retryable, status });
    },
    finishJob: async () => {
      log.finishJobs += 1;
      return behavior.finishJobStatus ?? "completed";
    },
    importEntry: async (args) => {
      log.imported.push(args);
      const error = behavior.importError?.(args);
      if (error) throw error;
      const outcome = behavior.outcome?.(args) ?? "created";
      return {
        entryId: outcome === "deleted_earlier" ? null : args.entryId,
        outcome,
      };
    },
    pauseForQuota: async () => {
      log.paused += 1;
    },
    registerPhoto: async (input) => {
      const error = behavior.register?.();
      if (error) throw error;
      log.registered.push(input.attachmentId);
    },
    releaseLease: async () => {
      log.released += 1;
    },
    uploadOriginal: async (path) => {
      const attempt = (attempts.get(path) ?? 0) + 1;
      attempts.set(path, attempt);
      const error = behavior.upload?.(path, attempt);
      if (error) throw error;
      log.uploads.push(path);
    },
  };
  return { gateway, log };
}

const photos = {
  read: async (photo: { zipPath: string }) =>
    photo.zipPath.startsWith("bad") ? Buffer.from("not an image") : tinyPng,
};

function run(gateway: ImportGateway, extra: Partial<Parameters<typeof runImport>[0]> = {}) {
  return runImport({
    gateway,
    options,
    ownerId,
    photos,
    sleep: async () => undefined,
    source: "markdown",
    ...extra,
  });
}

describe("sniffImageMime", () => {
  it("recognizes the image formats by their first bytes", () => {
    expect(sniffImageMime(tinyPng)).toBe("image/png");
    expect(sniffImageMime(tinyJpeg)).toBe("image/jpeg");
    expect(sniffImageMime(Buffer.from("hello world, not an image"))).toBeNull();
  });
});

describe("buildEntryArgs", () => {
  it("resolves the date, tags, and a stable Entry id", () => {
    const claimed = item(1);
    const args = buildEntryArgs(claimed, claimed.payload!, {
      options,
      ownerId,
      source: "markdown",
    });
    expect(args.entryId).toBe(importEntryId(ownerId, "markdown", "n1.md"));
    expect(args.datePrecision).toBe("day");
    expect(args.occurredStart).toBe("2024-05-12T16:00:00.000Z");
    expect(args.occurredTimezone).toBe("America/New_York");
    expect(args.tagNames).toContain("travel");
    expect(args.body).toBe("Hello from the source.");
    expect(args.contentHash).toBe("hash-1");
  });

  it("leaves an undated item unknown unless the person asks for the file time", () => {
    const claimed = item(2, {
      payload: payload({
        date: { precision: "unknown" },
        fileModifiedAt: "2023-01-02T03:04:05.000Z",
      }),
    });
    const base = { ownerId, source: "markdown" } as const;
    const left = buildEntryArgs(claimed, claimed.payload!, { ...base, options });
    expect(left.datePrecision).toBe("unknown");
    expect(left.occurredStart).toBeNull();
    const withFile = buildEntryArgs(claimed, claimed.payload!, {
      ...base,
      options: { ...options, undated: "file_time" },
    });
    expect(withFile.occurredStart).not.toBeNull();
  });

  it("passes a location as a manual address", () => {
    const claimed = item(3, { payload: payload({ locationLabel: "Lisbon, Portugal" }) });
    const args = buildEntryArgs(claimed, claimed.payload!, {
      options,
      ownerId,
      source: "markdown",
    });
    expect(args.primaryLocation).toEqual({ address: "Lisbon, Portugal", kind: "manual" });
  });
});

describe("runImport", () => {
  it("is busy when another run holds the lease", async () => {
    const { gateway, log } = fakeGateway([], { lease: false });
    expect(await run(gateway)).toEqual({ kind: "busy" });
    expect(log.finishJobs).toBe(0);
    expect(log.released).toBe(0);
  });

  it("imports text-only items and finishes the job when nothing is left", async () => {
    const { gateway, log } = fakeGateway([[item(1), item(2)]]);
    const result = await run(gateway);
    expect(result).toEqual({ kind: "finished", processed: 2, status: "completed" });
    expect(log.imported).toHaveLength(2);
    // import_entry settles a text-only item itself, so the run does not finish it again.
    expect(log.finished).toEqual([]);
    expect(log.released).toBe(1);
  });

  it("stops at its time budget and asks to be called again", async () => {
    let clock = 0;
    const { gateway, log } = fakeGateway([[item(1), item(2), item(3)]]);
    const result = await run(gateway, {
      budgetMs: 100,
      now: () => {
        clock += 60;
        return clock;
      },
    });
    expect(result.kind).toBe("more");
    expect(log.imported.length).toBeLessThan(3);
    expect(log.finishJobs).toBe(0);
    expect(log.released).toBe(1);
  });

  it("does not touch photos for an unchanged, changed, or deleted-earlier outcome", async () => {
    const media = { photos: [photo("p1")] };
    const outcomes: ImportEntryOutcome[] = [
      "unchanged",
      "changed_in_source",
      "deleted_earlier",
    ];
    const { gateway, log } = fakeGateway(
      [[item(1, {}, media), item(2, {}, media), item(3, {}, media)]],
      { outcome: (args) => outcomes[Number(args.itemId.slice(-1)) - 1] },
    );
    await run(gateway);
    expect(log.uploads).toEqual([]);
    expect(log.finished).toEqual([]);
  });

  it("uploads each photo, registers it, and finishes the item as imported", async () => {
    const media = { photos: [photo("p1"), photo("p2")] };
    const { gateway, log } = fakeGateway([[item(1, {}, media)]]);
    await run(gateway);
    expect(log.uploads).toHaveLength(2);
    expect(log.registered).toHaveLength(2);
    expect(log.uploads[0]).toContain(ownerId);
    expect(log.finished).toHaveLength(1);
    expect(log.finished[0]).toMatchObject({ reason: null, retryable: false, status: "imported" });
    expect(log.finished[0].media?.photos.map((p) => p.status)).toEqual(["done", "done"]);
  });

  it("picks up an Entry whose photos were left half done without importing it again", async () => {
    const entryId = importEntryId(ownerId, "markdown", "n1.md");
    const media = {
      photos: [{ ...photo("p1"), status: "done" as const }, photo("p2")],
    };
    const { gateway, log } = fakeGateway([
      [item(1, { entryId, media, status: "photos_pending" })],
    ]);
    await run(gateway);
    expect(log.imported).toEqual([]);
    expect(log.uploads).toHaveLength(1);
    expect(log.finished[0].status).toBe("imported");
  });

  it("retries an upload and then succeeds", async () => {
    const media = { photos: [photo("p1")] };
    const { gateway, log } = fakeGateway([[item(1, {}, media)]], {
      upload: (_path, attempt) => (attempt < 3 ? new Error("network") : null),
    });
    await run(gateway);
    expect(log.finished[0].status).toBe("imported");
    expect(log.uploads).toHaveLength(1);
  });

  it("marks the item partial and retryable when a photo keeps failing", async () => {
    const media = { photos: [photo("p1")] };
    const { gateway, log } = fakeGateway([[item(1, {}, media)]], {
      upload: () => new Error("network"),
    });
    await run(gateway);
    expect(log.finished[0]).toMatchObject({
      reason: "photo_upload_failed",
      retryable: true,
      status: "partial",
    });
    expect(log.finished[0].media?.photos[0].status).toBe("failed");
  });

  it("skips a photo that is not an image without failing the Entry", async () => {
    const media = { photos: [photo("p1"), { ...photo("bad"), zipPath: "bad.png" }] };
    const { gateway, log } = fakeGateway([[item(1, {}, media)]]);
    await run(gateway);
    expect(log.finished[0].status).toBe("imported");
    const states = log.finished[0].media?.photos.map((p) => [p.status, p.reason]);
    expect(states).toEqual([
      ["done", undefined],
      ["skipped", "photo_unsupported"],
    ]);
  });

  it("pauses the job when storage is full", async () => {
    const media = { photos: [photo("p1")] };
    const { gateway, log } = fakeGateway([[item(1, {}, media), item(2)]], {
      upload: () => new ImportQuotaError("storage limit"),
    });
    const result = await run(gateway);
    expect(result.kind).toBe("paused_quota");
    expect(log.paused).toBe(1);
    expect(log.finished).toEqual([]);
    expect(log.released).toBe(1);
  });

  it("records a final failure with its reason and keeps going", async () => {
    const { gateway, log } = fakeGateway([[item(1), item(2)]], {
      importError: (args) =>
        args.itemId === "item-1" ? new ImportItemError("entry_content_too_long") : null,
    });
    const result = await run(gateway);
    expect(result.kind).toBe("finished");
    expect(log.finished).toEqual([
      expect.objectContaining({
        itemId: "item-1",
        reason: "entry_content_too_long",
        retryable: false,
        status: "failed",
      }),
    ]);
    expect(log.imported).toHaveLength(2);
  });

  it("records an unexpected failure as retryable", async () => {
    const { gateway, log } = fakeGateway([[item(1)]], {
      importError: () => new Error("boom"),
    });
    await run(gateway);
    expect(log.finished[0]).toMatchObject({
      reason: "unexpected",
      retryable: true,
      status: "failed",
    });
  });

  it("fails an item whose text was removed", async () => {
    const { gateway, log } = fakeGateway([[item(1, { payload: null })]]);
    await run(gateway);
    expect(log.finished[0]).toMatchObject({
      reason: "payload_missing",
      retryable: false,
      status: "failed",
    });
  });

  it("stops quietly when the lease is lost", async () => {
    const { gateway, log } = fakeGateway([[item(1), item(2)]], {
      importError: () => new ImportLeaseLost(),
    });
    const result = await run(gateway);
    expect(result).toEqual({ kind: "stopped", processed: 0 });
    expect(log.finished).toEqual([]);
    expect(log.released).toBe(1);
  });
});
