import {
  createEntryRichText,
  plainTextDocument,
  plainTextFromDocument,
  trimEntryNote,
} from "@/lib/data/rich-text";
import { createEntryObjectPath } from "@/lib/data/entry-photo-input";
import { resolveImportDate } from "./dates";
import { importAttachmentId, importEntryId } from "./identity";
import { importLimits } from "./limits";
import type { ImportPayload } from "./scan";
import { entryTagNames } from "./tags";
import type {
  ImportItemMedia,
  ImportOptions,
  ImportPhotoState,
  ImportSource,
} from "./types";
import { ImportError } from "./zip";

export type ClaimedItem = {
  itemId: string;
  sourceKey: string;
  status: "pending" | "photos_pending";
  contentHash: string | null;
  payload: ImportPayload | null;
  media: ImportItemMedia | null;
  entryId: string | null;
};

export type ImportEntryArgs = {
  itemId: string;
  entryId: string;
  contentHash: string;
  title: string | null;
  body: string;
  bodyRich: unknown;
  occurredStart: string | null;
  occurredEnd: string | null;
  occurredTimezone: string;
  occurredLabel: string | null;
  datePrecision: string;
  tagNames: string[];
  primaryLocation: { kind: "manual"; address: string } | null;
  sourceCreatedAt: string | null;
  sourceModifiedAt: string | null;
};

export type ImportEntryOutcome =
  "created" | "unchanged" | "changed_in_source" | "deleted_earlier";

/** A failure with a code the item's result can carry. */
export class ImportItemError extends Error {
  constructor(
    public code: string,
    public retryable = false,
  ) {
    super(code);
  }
}

/** The run lost its lease: another run took over, or the job was cancelled. */
export class ImportLeaseLost extends Error {}

/** Storage or the project is out of room, which a person has to fix. */
export class ImportQuotaError extends Error {}

/** Everything a run needs from the outside, so the loop can be tested without a database. */
export interface ImportGateway {
  acquireLease(): Promise<string | null>;
  releaseLease(token: string): Promise<void>;
  claim(token: string, limit: number): Promise<ClaimedItem[]>;
  importEntry(args: ImportEntryArgs): Promise<{
    entryId: string | null;
    outcome: ImportEntryOutcome;
  }>;
  finishItem(
    itemId: string,
    status: "imported" | "skipped" | "failed" | "partial",
    reason: string | null,
    retryable: boolean,
    media: ImportItemMedia | null,
  ): Promise<void>;
  finishJob(): Promise<string>;
  pauseForQuota(): Promise<void>;
  /** Stores an original. An object that already exists counts as stored. */
  uploadOriginal(path: string, bytes: Buffer, mimeType: string): Promise<void>;
  registerPhoto(input: {
    entryId: string;
    attachmentId: string;
    objectPath: string;
    originalFilename: string;
    mimeType: string;
    byteSize: number;
  }): Promise<void>;
}

export type PhotoReader = {
  read(photo: ImportPhotoState): Promise<Buffer>;
};

export type RunInput = {
  ownerId: string;
  source: ImportSource;
  options: ImportOptions;
  gateway: ImportGateway;
  photos: PhotoReader;
  budgetMs?: number;
  now?: () => number;
  sleep?: (ms: number) => Promise<void>;
};

export type RunResult =
  | { kind: "busy" }
  | { kind: "more"; processed: number }
  | { kind: "finished"; status: string; processed: number }
  | { kind: "paused_quota"; processed: number }
  | { kind: "stopped"; processed: number };

export function sniffImageMime(
  head: Uint8Array,
):
  | "image/jpeg"
  | "image/png"
  | "image/webp"
  | "image/heic"
  | "image/heif"
  | null {
  const ascii = (start: number, end: number) =>
    String.fromCharCode(...head.subarray(start, end));
  if (head[0] === 0xff && head[1] === 0xd8 && head[2] === 0xff)
    return "image/jpeg";
  if (head[0] === 0x89 && ascii(1, 4) === "PNG") return "image/png";
  if (ascii(0, 4) === "RIFF" && ascii(8, 12) === "WEBP") return "image/webp";
  if (ascii(4, 8) === "ftyp") {
    const brand = ascii(8, 12);
    if (["heic", "heix", "hevc", "hevx", "heim", "heis"].includes(brand))
      return "image/heic";
    if (["mif1", "msf1"].includes(brand)) return "image/heif";
  }
  return null;
}

/** What import_entry takes for a scanned item, with the person's choices applied. */
export function buildEntryArgs(
  item: ClaimedItem,
  payload: ImportPayload,
  input: Pick<RunInput, "ownerId" | "source" | "options">,
): ImportEntryArgs {
  const date = resolveImportDate(payload.date, {
    fileModifiedAt: payload.fileModifiedAt,
    timezone: input.options.timezone,
    undated: input.options.undated,
  });
  const rich = createEntryRichText(payload.bodyRich);
  const text = rich?.text ?? plainTextFromDocument(payload.bodyRich);
  const trimmed = trimEntryNote(text, rich);
  const { body } = trimmed;
  const bodyRich =
    trimmed.bodyRich ??
    (body ? createEntryRichText(plainTextDocument(body)) : null);
  return {
    body,
    bodyRich,
    contentHash: item.contentHash ?? "",
    datePrecision: date.datePrecision,
    entryId: importEntryId(input.ownerId, input.source, item.sourceKey),
    itemId: item.itemId,
    occurredEnd: date.occurredEnd,
    occurredLabel: date.occurredLabel,
    occurredStart: date.occurredStart,
    occurredTimezone: date.occurredTimezone,
    primaryLocation: payload.locationLabel
      ? { address: payload.locationLabel.slice(0, 500), kind: "manual" }
      : null,
    sourceCreatedAt: payload.sourceCreatedAt,
    sourceModifiedAt: payload.sourceModifiedAt,
    tagNames: entryTagNames(payload, input.options).names,
    title: payload.title,
  };
}

const defaultSleep = (ms: number) =>
  new Promise<void>((resolve) => setTimeout(resolve, ms));

/**
 * One call's worth of importing. It takes the lease, works through claimed items one Entry at
 * a time until its time budget is spent, and says whether to call again. Everything it writes
 * is idempotent, so a call cut short anywhere is repeated safely.
 */
export async function runImport(input: RunInput): Promise<RunResult> {
  const now = input.now ?? Date.now;
  const budget = input.budgetMs ?? importLimits.runBudgetMs;
  const started = now();
  const { gateway } = input;
  const token = await gateway.acquireLease();
  if (!token) return { kind: "busy" };
  let processed = 0;
  try {
    while (now() - started < budget) {
      const items = await gateway.claim(token, importLimits.claimBatch);
      if (items.length === 0) {
        const status = await gateway.finishJob();
        return { kind: "finished", processed, status };
      }
      for (const item of items) {
        if (now() - started >= budget) break;
        const quota = await processItem(item, input);
        if (quota) {
          await gateway.pauseForQuota();
          return { kind: "paused_quota", processed };
        }
        processed += 1;
      }
    }
    return { kind: "more", processed };
  } catch (error) {
    if (error instanceof ImportLeaseLost) return { kind: "stopped", processed };
    throw error;
  } finally {
    await gateway.releaseLease(token).catch(() => undefined);
  }
}

/** Returns true when storage is full and the job should pause. */
async function processItem(
  item: ClaimedItem,
  input: RunInput,
): Promise<boolean> {
  const { gateway } = input;
  let entryId = item.entryId;
  try {
    if (item.status === "pending") {
      if (!item.payload || !item.contentHash) {
        await gateway.finishItem(
          item.itemId,
          "failed",
          "payload_missing",
          false,
          null,
        );
        return false;
      }
      const result = await gateway.importEntry(
        buildEntryArgs(item, item.payload, input),
      );
      // Anything but a new Entry was settled by the database.
      if (result.outcome !== "created" || !result.entryId) return false;
      entryId = result.entryId;
      if (!item.media?.photos.length) return false;
    }
    if (!entryId) {
      await gateway.finishItem(
        item.itemId,
        "failed",
        "entry_missing",
        false,
        null,
      );
      return false;
    }
    const media = item.media ?? { photos: [] };
    const outcome = await importPhotos(entryId, media, input);
    if (outcome.quota) return true;
    await gateway.finishItem(
      item.itemId,
      outcome.failed > 0 ? "partial" : "imported",
      outcome.failed > 0 ? "photo_upload_failed" : null,
      outcome.failed > 0,
      outcome.media,
    );
    return false;
  } catch (error) {
    if (error instanceof ImportLeaseLost) throw error;
    if (error instanceof ImportQuotaError) return true;
    const known = error instanceof ImportItemError;
    await gateway
      .finishItem(
        item.itemId,
        "failed",
        known ? error.code : "unexpected",
        known ? error.retryable : true,
        null,
      )
      .catch(() => undefined);
    return false;
  }
}

async function importPhotos(
  entryId: string,
  media: ImportItemMedia,
  input: RunInput,
): Promise<{ media: ImportItemMedia; failed: number; quota: boolean }> {
  const photos = media.photos.map((photo) => ({ ...photo }));
  const queue = photos.filter(
    (photo) => photo.status === "pending" || photo.status === "failed",
  );
  let quota = false;
  let next = 0;
  const worker = async () => {
    while (!quota && next < queue.length) {
      const photo = queue[next];
      next += 1;
      try {
        await importPhoto(entryId, photo, input);
        photo.status = "done";
        delete photo.reason;
      } catch (error) {
        if (error instanceof ImportQuotaError) {
          quota = true;
        } else if (error instanceof ImportItemError && !error.retryable) {
          photo.status = "skipped";
          photo.reason = error.code;
        } else {
          photo.status = "failed";
          photo.reason =
            error instanceof ImportItemError
              ? error.code
              : "photo_upload_failed";
        }
      }
    }
  };
  await Promise.all(
    Array.from(
      { length: Math.min(importLimits.photoUploadConcurrency, queue.length) },
      worker,
    ),
  );
  return {
    failed: photos.filter((photo) => photo.status === "failed").length,
    media: { photos },
    quota,
  };
}

async function importPhoto(
  entryId: string,
  photo: ImportPhotoState,
  input: RunInput,
) {
  const sleep = input.sleep ?? defaultSleep;
  let bytes: Buffer;
  try {
    bytes = await input.photos.read(photo);
  } catch (error) {
    if (error instanceof ImportError && error.code === "file_too_large")
      throw new ImportItemError("photo_too_large");
    throw new ImportItemError("photo_missing");
  }
  const mimeType = sniffImageMime(bytes);
  if (!mimeType) throw new ImportItemError("photo_unsupported");
  const attachmentId = importAttachmentId(entryId, photo.key);
  const objectPath = createEntryObjectPath(
    input.ownerId,
    entryId,
    attachmentId,
    mimeType,
  );
  if (!objectPath) throw new ImportItemError("photo_unsupported");

  let last: unknown;
  for (
    let attempt = 0;
    attempt < importLimits.photoUploadAttempts;
    attempt += 1
  ) {
    try {
      await input.gateway.uploadOriginal(objectPath, bytes, mimeType);
      // Upload first, register second, like capture: no row ever points at missing bytes.
      await input.gateway.registerPhoto({
        attachmentId,
        byteSize: bytes.length,
        entryId,
        mimeType,
        objectPath,
        originalFilename: photo.originalFilename.slice(0, 255),
      });
      return;
    } catch (error) {
      if (error instanceof ImportQuotaError) throw error;
      if (error instanceof ImportItemError && !error.retryable) throw error;
      last = error;
      await sleep(250 * 2 ** attempt);
    }
  }
  throw last instanceof Error
    ? last
    : new ImportItemError("photo_upload_failed", true);
}
