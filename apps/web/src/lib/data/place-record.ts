import {
  firstTimeImageMimeTypes,
  type FirstTimeImageMimeType,
} from "./first-time-input";
import { isWikiItemKind, type WikiItemKind } from "./wiki-item";

export type PlaceAttachment = {
  bucketId: string;
  byteSize: number | null;
  createdAt: string;
  id: string;
  imageUrl: string | null;
  mimeType: FirstTimeImageMimeType;
  objectPath: string;
  originalFilename: string | null;
  pixelHeight: number | null;
  pixelWidth: number | null;
};

export type PlaceLinkedEntry = {
  attachments: PlaceAttachment[];
  body: string;
  datePrecision: string;
  id: string;
  inboxStatus: string;
  itemKind: WikiItemKind;
  itemSubtype: string;
  occurredEnd: string | null;
  occurredLabel: string | null;
  occurredStart: string | null;
  occurredTimezone: string | null;
  relationship: string;
  revision: number;
  title: string;
  updatedAt: string;
};

export type PlaceRecord = {
  address: string | null;
  city: string | null;
  country: string | null;
  createdAt: string;
  homeCount: number;
  id: string;
  latitude: number | null;
  linkedEntries: PlaceLinkedEntry[];
  linkedEntryCount: number;
  longitude: number | null;
  name: string;
  notes: string | null;
  region: string | null;
  revision: number;
  totalCount: number;
  updatedAt: string;
};

export type PlaceLinkOption = {
  id: string;
  itemKind: WikiItemKind;
  itemSubtype: string;
  title: string;
  updatedAt: string;
};

export function parsePlaceRows(value: unknown): PlaceRecord[] | null {
  if (!Array.isArray(value)) return null;
  const places: PlaceRecord[] = [];
  for (const item of value) {
    const place = parsePlaceRow(item);
    if (!place) return null;
    places.push(place);
  }
  return places;
}

export function parsePlaceLinkOptions(
  value: unknown,
): PlaceLinkOption[] | null {
  if (!Array.isArray(value)) return null;
  const options: PlaceLinkOption[] = [];
  for (const item of value) {
    if (
      !isRecord(item) ||
      typeof item.id !== "string" ||
      !nullableString(item.title) ||
      !nullableString(item.body) ||
      !isWikiItemKind(item.item_kind) ||
      typeof item.item_subtype !== "string" ||
      typeof item.updated_at !== "string"
    ) {
      return null;
    }
    options.push({
      id: item.id,
      itemKind: item.item_kind,
      itemSubtype: item.item_subtype,
      title: entryOptionTitle(item.title, item.body),
      updatedAt: item.updated_at,
    });
  }
  return options;
}

export function placeLocationLabel(place: PlaceRecord) {
  const locality = [place.city, place.region, place.country].filter(Boolean);
  if (place.address && locality.length > 0) {
    return `${place.address} · ${locality.join(", ")}`;
  }
  return place.address || locality.join(", ") || "Location details not added";
}

export function placeCoordinateLabel(place: PlaceRecord) {
  if (place.latitude === null || place.longitude === null) return null;
  return `${formatCoordinate(place.latitude, "N", "S")}, ${formatCoordinate(place.longitude, "E", "W")}`;
}

export function placeCover(place: PlaceRecord) {
  return place.linkedEntries.flatMap((entry) => entry.attachments)[0] ?? null;
}

function parsePlaceRow(value: unknown): PlaceRecord | null {
  if (
    !isRecord(value) ||
    typeof value.place_id !== "string" ||
    typeof value.name !== "string" ||
    !nullableString(value.address) ||
    !nullableString(value.city) ||
    !nullableString(value.region) ||
    !nullableString(value.country) ||
    !nullableNumber(value.latitude) ||
    !nullableNumber(value.longitude) ||
    !nullableString(value.notes) ||
    typeof value.revision !== "number" ||
    typeof value.created_at !== "string" ||
    typeof value.updated_at !== "string" ||
    !countLike(value.linked_entry_count) ||
    !countLike(value.home_count) ||
    !countLike(value.total_count)
  ) {
    return null;
  }

  const linkedEntries = parseLinkedEntries(value.linked_entries);
  if (!linkedEntries) return null;

  return {
    address: value.address,
    city: value.city,
    country: value.country,
    createdAt: value.created_at,
    homeCount: safeCount(value.home_count),
    id: value.place_id,
    latitude: value.latitude,
    linkedEntries,
    linkedEntryCount: safeCount(value.linked_entry_count),
    longitude: value.longitude,
    name: value.name,
    notes: value.notes,
    region: value.region,
    revision: value.revision,
    totalCount: safeCount(value.total_count),
    updatedAt: value.updated_at,
  };
}

function parseLinkedEntries(value: unknown): PlaceLinkedEntry[] | null {
  if (!Array.isArray(value)) return null;
  const entries: PlaceLinkedEntry[] = [];
  for (const item of value) {
    if (
      !isRecord(item) ||
      typeof item.id !== "string" ||
      !nullableString(item.title) ||
      typeof item.body !== "string" ||
      !isWikiItemKind(item.item_kind) ||
      typeof item.item_subtype !== "string" ||
      typeof item.inbox_status !== "string" ||
      !nullableString(item.occurred_start) ||
      !nullableString(item.occurred_end) ||
      typeof item.date_precision !== "string" ||
      !nullableString(item.occurred_label) ||
      !nullableString(item.occurred_timezone) ||
      typeof item.revision !== "number" ||
      typeof item.updated_at !== "string" ||
      typeof item.relationship !== "string"
    ) {
      return null;
    }
    const attachments = parseAttachments(item.attachments);
    if (!attachments) return null;
    entries.push({
      attachments,
      body: item.body,
      datePrecision: item.date_precision,
      id: item.id,
      inboxStatus: item.inbox_status,
      itemKind: item.item_kind,
      itemSubtype: item.item_subtype,
      occurredEnd: item.occurred_end,
      occurredLabel: item.occurred_label,
      occurredStart: item.occurred_start,
      occurredTimezone: item.occurred_timezone,
      relationship: item.relationship,
      revision: item.revision,
      title: item.title || "Untitled Entry",
      updatedAt: item.updated_at,
    });
  }
  return entries;
}

function parseAttachments(value: unknown): PlaceAttachment[] | null {
  if (!Array.isArray(value)) return null;
  const attachments: PlaceAttachment[] = [];
  for (const item of value) {
    if (
      !isRecord(item) ||
      typeof item.id !== "string" ||
      typeof item.bucket_id !== "string" ||
      typeof item.object_path !== "string" ||
      !nullableString(item.original_filename) ||
      typeof item.mime_type !== "string" ||
      !firstTimeImageMimeTypes.includes(
        item.mime_type as FirstTimeImageMimeType,
      ) ||
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
      mimeType: item.mime_type as FirstTimeImageMimeType,
      objectPath: item.object_path,
      originalFilename: item.original_filename,
      pixelHeight: item.pixel_height,
      pixelWidth: item.pixel_width,
    });
  }
  return attachments;
}

function formatCoordinate(value: number, positive: string, negative: string) {
  const rounded = Math.abs(value)
    .toFixed(4)
    .replace(/0+$/, "")
    .replace(/\.$/, "");
  return `${rounded}°${value < 0 ? negative : positive}`;
}

function entryOptionTitle(title: string | null, body: string | null) {
  const normalizedTitle = title?.trim();
  if (normalizedTitle) return normalizedTitle;
  const normalizedBody = body?.trim();
  if (!normalizedBody) return "Untitled Entry";
  return normalizedBody.length > 80
    ? `${normalizedBody.slice(0, 80).trimEnd()}...`
    : normalizedBody;
}

function nullableNumber(value: unknown): value is number | null {
  return (
    value === null || (typeof value === "number" && Number.isFinite(value))
  );
}

function nullableString(value: unknown) {
  return value === null || typeof value === "string";
}

function countLike(value: unknown): value is number | string {
  return typeof value === "number" || typeof value === "string";
}

function safeCount(value: number | string) {
  const count = typeof value === "number" ? value : Number(value);
  return Number.isSafeInteger(count) && count >= 0 ? count : 0;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}
