import {
  occurrenceSpanLabel,
  occurrenceDurationLabel,
  type Occurrence,
} from "./occurrence";
import {
  firstTimeImageMimeTypes,
  type FirstTimeImageMimeType,
} from "./first-time-input";
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
  mimeType: FirstTimeImageMimeType;
  objectPath: string;
  originalFilename: string | null;
  pixelHeight: number | null;
  pixelWidth: number | null;
};

export type HomeRecord = {
  address: string | null;
  attachments: HomeAttachment[];
  body: string;
  city: string | null;
  collectionNames: string[];
  country: string | null;
  datePrecision: HomeDatePrecision;
  id: string;
  latitude: number | null;
  longitude: number | null;
  moveInReason: string | null;
  moveOutReason: string | null;
  occurredEnd: string | null;
  occurredLabel: string | null;
  occurredStart: string | null;
  occurredTimezone: string;
  placeId: string;
  placeName: string;
  placeNotes: string | null;
  region: string | null;
  revision: number;
  tagNames: string[];
  timelineTrackId: string | null;
  timelineTrackName: string | null;
  title: string;
  totalCount: number;
  updatedAt: string;
};

export type HomePlaceOption = {
  address: string | null;
  city: string | null;
  country: string | null;
  id: string;
  latitude: number | null;
  longitude: number | null;
  name: string;
  notes: string | null;
  region: string | null;
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

export function parseHomePlaceOptions(
  value: unknown,
): HomePlaceOption[] | null {
  if (!Array.isArray(value)) {
    return null;
  }

  const places: HomePlaceOption[] = [];

  for (const item of value) {
    if (
      !isRecord(item) ||
      typeof item.id !== "string" ||
      typeof item.name !== "string" ||
      !nullableString(item.address) ||
      !nullableString(item.city) ||
      !nullableString(item.region) ||
      !nullableString(item.country) ||
      !nullableNumber(item.latitude) ||
      !nullableNumber(item.longitude) ||
      !nullableString(item.notes)
    ) {
      return null;
    }

    places.push({
      address: item.address,
      city: item.city,
      country: item.country,
      id: item.id,
      latitude: item.latitude,
      longitude: item.longitude,
      name: item.name,
      notes: item.notes,
      region: item.region,
    });
  }

  return places;
}

export function homeLocationLabel(home: HomeRecord) {
  const parts = [home.city, home.region, home.country].filter(
    (part): part is string => Boolean(part),
  );

  return [...new Set(parts)].join(", ") || home.placeName;
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
    typeof value.place_id !== "string" ||
    typeof value.place_name !== "string" ||
    !nullableString(value.address) ||
    !nullableString(value.city) ||
    !nullableString(value.region) ||
    !nullableString(value.country) ||
    !nullableNumber(value.latitude) ||
    !nullableNumber(value.longitude) ||
    !nullableString(value.place_notes) ||
    !nullableString(value.timeline_track_id) ||
    !nullableString(value.timeline_track_name) ||
    !stringArray(value.collection_names) ||
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
    address: value.address,
    attachments,
    body: value.body,
    city: value.city,
    collectionNames: value.collection_names,
    country: value.country,
    datePrecision: value.date_precision as HomeDatePrecision,
    id: value.entry_id,
    latitude: value.latitude,
    longitude: value.longitude,
    moveInReason: value.move_in_reason,
    moveOutReason: value.move_out_reason,
    occurredEnd: value.occurred_end,
    occurredLabel: value.occurred_label,
    occurredStart: value.occurred_start,
    occurredTimezone: value.occurred_timezone ?? "UTC",
    placeId: value.place_id,
    placeName: value.place_name,
    placeNotes: value.place_notes,
    region: value.region,
    revision: value.revision,
    tagNames: value.tag_names,
    timelineTrackId: value.timeline_track_id,
    timelineTrackName: value.timeline_track_name,
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
