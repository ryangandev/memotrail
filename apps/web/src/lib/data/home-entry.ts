export type HomeAttachment = {
  bucketId: string;
  byteSize: number | null;
  id: string;
  imageUrl: string | null;
  mimeType: string;
  objectPath: string;
  originalFilename: string | null;
  pixelHeight: number | null;
  pixelWidth: number | null;
};

export type HomeEntry = {
  attachments: HomeAttachment[];
  body: string;
  createdAt: string;
  datePrecision: string;
  id: string;
  itemKind: WikiItemKind;
  itemSubtype: string;
  occurredEnd: string | null;
  occurredLabel: string | null;
  occurredStart: string | null;
  occurredTimezone: string | null;
  revision: number;
  tagNames: string[];
  /** The stored title, blank when the Entry has none. */
  title: string;
  updatedAt: string;
};

export function parseHomeEntries(value: unknown): HomeEntry[] | null {
  if (!Array.isArray(value)) {
    return null;
  }

  const entries: HomeEntry[] = [];

  for (const item of value) {
    const entry = parseHomeEntry(item);

    if (!entry) {
      return null;
    }

    entries.push(entry);
  }

  return entries;
}

export function parseHomeEntry(value: unknown): HomeEntry | null {
  if (!isRecord(value)) {
    return null;
  }

  const attachments = parseAttachments(value.attachments);

  if (
    !attachments ||
    typeof value.entry_id !== "string" ||
    typeof value.title !== "string" ||
    typeof value.body !== "string" ||
    !isWikiItemKind(value.item_kind) ||
    typeof value.item_subtype !== "string" ||
    !nullableString(value.occurred_start) ||
    !nullableString(value.occurred_end) ||
    typeof value.date_precision !== "string" ||
    !nullableString(value.occurred_label) ||
    !nullableString(value.occurred_timezone) ||
    typeof value.revision !== "number" ||
    !Number.isSafeInteger(value.revision) ||
    value.revision < 1 ||
    typeof value.created_at !== "string" ||
    typeof value.updated_at !== "string" ||
    !stringArray(value.tag_names)
  ) {
    return null;
  }

  return {
    attachments,
    body: value.body,
    createdAt: value.created_at,
    datePrecision: value.date_precision,
    id: value.entry_id,
    itemKind: value.item_kind,
    itemSubtype: value.item_subtype,
    occurredEnd: value.occurred_end,
    occurredLabel: value.occurred_label,
    occurredStart: value.occurred_start,
    occurredTimezone: value.occurred_timezone,
    revision: value.revision,
    tagNames: value.tag_names,
    title: value.title,
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
      typeof item.attachment_id !== "string" ||
      typeof item.bucket_id !== "string" ||
      typeof item.object_path !== "string" ||
      !nullableString(item.original_filename) ||
      typeof item.mime_type !== "string" ||
      !nullableNumber(item.byte_size) ||
      !nullableNumber(item.pixel_width) ||
      !nullableNumber(item.pixel_height)
    ) {
      return null;
    }

    attachments.push({
      bucketId: item.bucket_id,
      byteSize: item.byte_size,
      id: item.attachment_id,
      imageUrl: null,
      mimeType: item.mime_type,
      objectPath: item.object_path,
      originalFilename: item.original_filename,
      pixelHeight: item.pixel_height,
      pixelWidth: item.pixel_width,
    });
  }

  return attachments;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function nullableString(value: unknown): value is string | null {
  return value === null || typeof value === "string";
}

function nullableNumber(value: unknown): value is number | null {
  return value === null || typeof value === "number";
}

function stringArray(value: unknown): value is string[] {
  return (
    Array.isArray(value) && value.every((item) => typeof item === "string")
  );
}
import { isWikiItemKind, type WikiItemKind } from "./wiki-item";
