import { tagNamesLimitMessage } from "./organization";
import { parseTagNames } from "./inbox-review";
import { validateOccurrence } from "./occurrence";

export const firstTimeBodyLimit = 50_000;
export const firstTimeLabelLimit = 200;
export const firstTimeTitleLimit = 200;
export const firstTimePhotoLimit = 12;
export const firstTimePhotoSizeLimit = 50 * 1024 * 1024;

export const firstTimeDatePrecisions = [
  "exact",
  "day",
  "month",
  "year",
  "approximate",
  "age",
  "range",
  "unknown",
] as const;

export const firstTimeImageMimeTypes = [
  "image/jpeg",
  "image/png",
  "image/webp",
  "image/heic",
  "image/heif",
] as const;

export type FirstTimeDatePrecision = (typeof firstTimeDatePrecisions)[number];
export type FirstTimeImageMimeType = (typeof firstTimeImageMimeTypes)[number];

export type FirstTimeEntryInput = {
  body: string;
  datePrecision: FirstTimeDatePrecision;
  id: string | null;
  occurredLabel: string | null;
  occurredStart: string | null;
  occurredEnd?: string | null;
  occurredTimezone: string | null;
  revision: number | null;
  tagNames: string[];
  title: string;
};

export type FirstTimeAttachmentInput = {
  attachmentId: string;
  byteSize: number;
  entryId: string;
  mimeType: FirstTimeImageMimeType;
  objectPath: string;
  originalFilename: string | null;
  pixelHeight: number | null;
  pixelWidth: number | null;
};

type Parsed<T> =
  { data: T; success: true } | { message: string; success: false };

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const mimeTypeExtensions: Record<FirstTimeImageMimeType, string> = {
  "image/heic": "heic",
  "image/heif": "heif",
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
};

export function parseFirstTimeEntryInput(
  input: unknown,
): Parsed<FirstTimeEntryInput> {
  if (!isRecord(input)) {
    return invalid("This First Time is invalid. Refresh and try again.");
  }

  const title = typeof input.title === "string" ? input.title.trim() : "";
  const body = typeof input.body === "string" ? input.body.trim() : "";
  const occurredLabel =
    typeof input.occurredLabel === "string"
      ? input.occurredLabel.trim() || null
      : null;
  const occurredTimezone =
    typeof input.occurredTimezone === "string"
      ? input.occurredTimezone.trim() || null
      : null;
  const tagNames = parseTagNames(input.tagNames);

  if (!title) {
    return invalid("Add a title for this First Time.");
  }

  if (title.length > firstTimeTitleLimit) {
    return invalid(`Titles can be up to ${firstTimeTitleLimit} characters.`);
  }

  if (body.length > firstTimeBodyLimit) {
    return invalid(`Notes can be up to ${firstTimeBodyLimit} characters.`);
  }

  if (occurredLabel && occurredLabel.length > firstTimeLabelLimit) {
    return invalid(
      `Human date labels can be up to ${firstTimeLabelLimit} characters.`,
    );
  }

  if (!tagNames) {
    return invalid(tagNamesLimitMessage);
  }

  if (
    typeof input.datePrecision !== "string" ||
    !firstTimeDatePrecisions.includes(
      input.datePrecision as FirstTimeDatePrecision,
    )
  ) {
    return invalid("Choose a valid date precision.");
  }

  const datePrecision = input.datePrecision as FirstTimeDatePrecision;
  const occurredStart =
    typeof input.occurredStart === "string" && input.occurredStart
      ? validIsoDate(input.occurredStart)
      : null;

  if (input.occurredStart && !occurredStart) {
    return invalid("Choose a valid date or leave it empty.");
  }

  if (!occurredStart) {
    if (!["age", "approximate", "unknown"].includes(datePrecision)) {
      return invalid(
        "Add a date, or use Approximate, Age-based, or Unknown precision.",
      );
    }

    if (occurredTimezone) {
      return invalid("Do not attach a time zone when no date is stored.");
    }
  } else if (!occurredTimezone || occurredTimezone.length > 100) {
    return invalid("Choose a valid occurrence time zone.");
  }

  if (!isFirstTimeEntryIdentity(input.id, input.revision)) {
    return invalid(
      "This First Time version is invalid. Refresh and try again.",
    );
  }

  const occurredEnd =
    typeof input.occurredEnd === "string" && input.occurredEnd
      ? validIsoDate(input.occurredEnd)
      : null;
  if (input.occurredEnd && !occurredEnd)
    return invalid("Choose a valid end date.");
  const occurrenceError = validateOccurrence({
    datePrecision,
    occurredAt: occurredStart,
    occurredEnd,
    occurredLabel,
    occurredTimezone: occurredTimezone ?? "UTC",
  });
  if (occurrenceError) return invalid(occurrenceError);

  return {
    data: {
      body,
      datePrecision,
      id: input.id as string | null,
      occurredLabel,
      occurredStart,
      occurredEnd,
      occurredTimezone,
      revision: input.revision as number | null,
      tagNames,
      title,
    },
    success: true,
  };
}

export function parseFirstTimeAttachmentInput(
  input: unknown,
): Parsed<FirstTimeAttachmentInput> {
  if (!isRecord(input)) {
    return invalid("This photo is invalid. Select it again.");
  }

  const mimeType = normalizeFirstTimeImageMimeType(input.mimeType);
  const originalFilename =
    typeof input.originalFilename === "string"
      ? input.originalFilename.trim() || null
      : null;

  if (
    typeof input.attachmentId !== "string" ||
    !uuidPattern.test(input.attachmentId) ||
    typeof input.entryId !== "string" ||
    !uuidPattern.test(input.entryId) ||
    typeof input.objectPath !== "string" ||
    !input.objectPath.trim()
  ) {
    return invalid("This photo reference is invalid. Select it again.");
  }

  if (!mimeType) {
    return invalid("Use a JPEG, PNG, WebP, HEIC, or HEIF image.");
  }

  if (
    typeof input.byteSize !== "number" ||
    !Number.isSafeInteger(input.byteSize) ||
    input.byteSize < 1 ||
    input.byteSize > firstTimePhotoSizeLimit
  ) {
    return invalid("Each photo must be no larger than 50 MB.");
  }

  if (originalFilename && originalFilename.length > 255) {
    return invalid("Photo filenames can be up to 255 characters.");
  }

  const pixelWidth = optionalPositiveInteger(input.pixelWidth);
  const pixelHeight = optionalPositiveInteger(input.pixelHeight);

  if (pixelWidth === undefined || pixelHeight === undefined) {
    return invalid("This photo has invalid dimensions.");
  }

  return {
    data: {
      attachmentId: input.attachmentId,
      byteSize: input.byteSize,
      entryId: input.entryId,
      mimeType,
      objectPath: input.objectPath.trim(),
      originalFilename,
      pixelHeight,
      pixelWidth,
    },
    success: true,
  };
}

export function createFirstTimeObjectPath(
  ownerId: string,
  entryId: string,
  attachmentId: string,
  mimeType: string,
) {
  const normalizedMimeType = normalizeFirstTimeImageMimeType(mimeType);

  if (
    !uuidPattern.test(ownerId) ||
    !uuidPattern.test(entryId) ||
    !uuidPattern.test(attachmentId) ||
    !normalizedMimeType
  ) {
    return null;
  }

  return `${ownerId}/${entryId}/${attachmentId}.${mimeTypeExtensions[normalizedMimeType]}`;
}

export function normalizeFirstTimeImageMimeType(value: unknown) {
  if (typeof value !== "string") {
    return null;
  }

  const normalized = value.trim().toLocaleLowerCase();
  return firstTimeImageMimeTypes.includes(normalized as FirstTimeImageMimeType)
    ? (normalized as FirstTimeImageMimeType)
    : null;
}

export function inferFirstTimeImageMimeType(
  name: string,
  declaredType: string,
) {
  const declared = normalizeFirstTimeImageMimeType(declaredType);

  if (declared) {
    return declared;
  }

  const extension = name.trim().toLocaleLowerCase().split(".").pop();
  const inferred: Record<string, FirstTimeImageMimeType> = {
    heic: "image/heic",
    heif: "image/heif",
    jpeg: "image/jpeg",
    jpg: "image/jpeg",
    png: "image/png",
    webp: "image/webp",
  };

  return extension ? (inferred[extension] ?? null) : null;
}

export function isFirstTimeEntryIdentity(
  id: unknown,
  revision: unknown,
): boolean {
  return id === null
    ? revision === null
    : typeof id === "string" &&
        uuidPattern.test(id) &&
        typeof revision === "number" &&
        Number.isSafeInteger(revision) &&
        revision >= 1;
}

export function isFirstTimeUuid(value: unknown): value is string {
  return typeof value === "string" && uuidPattern.test(value);
}

function validIsoDate(value: string) {
  if (!/^\d{4}-\d{2}-\d{2}T/.test(value) || value.startsWith("0000-"))
    return null;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return null;
  const day = new Date(`${value.slice(0, 10)}T12:00:00Z`);
  if (
    !Number.isFinite(day.getTime()) ||
    day.toISOString().slice(0, 10) !== value.slice(0, 10)
  )
    return null;
  // Do not round a database instant to JavaScript's millisecond precision.
  return /\.\d{4,}(Z|[+-]\d{2}:\d{2})$/.test(value)
    ? value
    : date.toISOString();
}

function optionalPositiveInteger(value: unknown): number | null | undefined {
  if (value === null || value === undefined) {
    return null;
  }

  return typeof value === "number" && Number.isSafeInteger(value) && value > 0
    ? value
    : undefined;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function invalid(message: string) {
  return { message, success: false } as const;
}
