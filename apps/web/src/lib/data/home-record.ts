import {
  occurrenceSpanLabel,
  occurrenceDurationLabel,
  type Occurrence,
} from "./occurrence";
import {
  entryImageMimeTypes,
  type EntryImageMimeType,
} from "./entry-photo-input";
import {
  locationDisplayLabel,
  type ExistingLocation,
} from "@/lib/locations/location";
import {
  homeDatePrecisions,
  type HomeDatePrecision,
} from "./home-record-input";

export type HomeAttachment = {
  bucketId: string;
  byteSize: number | null;
  createdAt: string;
  id: string;
  imageUrl: string | null;
  mimeType: EntryImageMimeType;
  objectPath: string;
  originalFilename: string | null;
  pixelHeight: number | null;
  pixelWidth: number | null;
};

export type HomeRecord = {
  attachments: HomeAttachment[];
  body: string;
  datePrecision: HomeDatePrecision;
  id: string;
  location: ExistingLocation | null;
  moveInReason: string | null;
  moveOutReason: string | null;
  occurredEnd: string | null;
  occurredLabel: string | null;
  occurredStart: string | null;
  occurredTimezone: string;
  revision: number;
  tagNames: string[];
  title: string;
  totalCount: number;
  updatedAt: string;
};

export function parseHomeRows(value: unknown): HomeRecord[] | null {
  if (!Array.isArray(value)) {
    return null;
  }

  const records: HomeRecord[] = [];

  for (const item of value) {
    const record = parseHomeRow(item);
    if (!record) {
      return null;
    }
    records.push(record);
  }

  return records;
}

export function homeLocationLabel(home: HomeRecord) {
  if (!home.location) return "Location not added";
  const parts = [
    home.location.city,
    home.location.region,
    home.location.country,
  ].filter((part): part is string => Boolean(part));

  return [...new Set(parts)].join(", ") || locationDisplayLabel(home.location);
}

export function homeOccurrence(value: HomeRecord): Occurrence {
  return {
    occurredAt: value.occurredStart,
    occurredEnd: value.occurredEnd,
    occurredLabel: value.occurredLabel,
    occurredTimezone: value.occurredTimezone,
    datePrecision: value.datePrecision,
  };
}
export function homeRangeLabel(value: HomeRecord) {
  return occurrenceSpanLabel(homeOccurrence(value));
}
export function homeDurationLabel(value: HomeRecord, now = new Date()) {
  return occurrenceDurationLabel(homeOccurrence(value), now);
}

function parseHomeRow(value: unknown): HomeRecord | null {
  if (
    !isRecord(value) ||
    typeof value.entry_id !== "string" ||
    typeof value.title !== "string" ||
    typeof value.body !== "string" ||
    !nullableString(value.occurred_start) ||
    (value.occurred_start === null &&
      !["age", "approximate", "unknown"].includes(
        String(value.date_precision),
      )) ||
    !nullableString(value.occurred_end) ||
    typeof value.date_precision !== "string" ||
    !homeDatePrecisions.includes(value.date_precision as HomeDatePrecision) ||
    !nullableString(value.occurred_label) ||
    !nullableString(value.occurred_timezone) ||
    typeof value.revision !== "number" ||
    typeof value.updated_at !== "string" ||
    !nullableString(value.move_in_reason) ||
    !nullableString(value.move_out_reason) ||
    !stringArray(value.tag_names) ||
    typeof value.total_count !== "number"
  ) {
    return null;
  }

  const attachments = parseAttachments(value.attachments);
  if (!attachments) {
    return null;
  }

  return {
    attachments,
    body: value.body,
    datePrecision: value.date_precision as HomeDatePrecision,
    id: value.entry_id,
    location: null,
    moveInReason: value.move_in_reason,
    moveOutReason: value.move_out_reason,
    occurredEnd: value.occurred_end,
    occurredLabel: value.occurred_label,
    occurredStart: value.occurred_start,
    occurredTimezone: value.occurred_timezone ?? "UTC",
    revision: value.revision,
    tagNames: value.tag_names,
    title: value.title,
    totalCount: value.total_count,
    updatedAt: value.updated_at,
  };
}

function parseAttachments(value: unknown): HomeAttachment[] | null {
  if (!Array.isArray(value)) {
    return null;
  }

  const attachments: HomeAttachment[] = [];

  for (const item of value) {
    if (
      !isRecord(item) ||
      typeof item.id !== "string" ||
      typeof item.bucket_id !== "string" ||
      typeof item.object_path !== "string" ||
      !nullableString(item.original_filename) ||
      typeof item.mime_type !== "string" ||
      !entryImageMimeTypes.includes(item.mime_type as EntryImageMimeType) ||
      !nullableNumber(item.byte_size) ||
      !nullableNumber(item.pixel_width) ||
      !nullableNumber(item.pixel_height) ||
      typeof item.created_at !== "string"
    ) {
      return null;
    }

    attachments.push({
      bucketId: item.bucket_id,
      byteSize: item.byte_size,
      createdAt: item.created_at,
      id: item.id,
      imageUrl: null,
      mimeType: item.mime_type as EntryImageMimeType,
      objectPath: item.object_path,
      originalFilename: item.original_filename,
      pixelHeight: item.pixel_height,
      pixelWidth: item.pixel_width,
    });
  }

  return attachments;
}

function stringArray(value: unknown): value is string[] {
  return (
    Array.isArray(value) && value.every((item) => typeof item === "string")
  );
}

function nullableNumber(value: unknown): value is number | null {
  return value === null || typeof value === "number";
}

function nullableString(value: unknown): value is string | null {
  return value === null || typeof value === "string";
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}
