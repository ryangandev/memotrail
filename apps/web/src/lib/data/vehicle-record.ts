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
  vehicleDatePrecisions,
  type VehicleDatePrecision,
} from "./vehicle-record-input";

export type VehicleAttachment = {
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

export type VehicleRecord = {
  attachments: VehicleAttachment[];
  body: string;
  collectionNames: string[];
  color: string | null;
  datePrecision: VehicleDatePrecision;
  id: string;
  make: string | null;
  model: string | null;
  modelYear: number | null;
  occurredEnd: string | null;
  occurredLabel: string | null;
  occurredStart: string | null;
  occurredTimezone: string;
  revision: number;
  tagNames: string[];
  timelineTrackId: string | null;
  timelineTrackName: string | null;
  title: string;
  totalCount: number;
  updatedAt: string;
};

export function parseVehicleRows(value: unknown): VehicleRecord[] | null {
  if (!Array.isArray(value)) return null;
  const records: VehicleRecord[] = [];

  for (const item of value) {
    const record = parseVehicleRow(item);
    if (!record) return null;
    records.push(record);
  }
  return records;
}

export function vehicleFactsLabel(vehicle: VehicleRecord) {
  const identity = [vehicle.modelYear?.toString(), vehicle.make, vehicle.model]
    .filter((value): value is string => Boolean(value))
    .join(" ");
  return (
    [identity, vehicle.color].filter(Boolean).join(" · ") ||
    "Details not recorded"
  );
}

export function vehicleOccurrence(value: VehicleRecord): Occurrence {
  return {
    occurredAt: value.occurredStart,
    occurredEnd: value.occurredEnd,
    occurredLabel: value.occurredLabel,
    occurredTimezone: value.occurredTimezone,
    datePrecision: value.datePrecision,
  };
}
export function vehicleRangeLabel(value: VehicleRecord) {
  return occurrenceSpanLabel(vehicleOccurrence(value));
}
export function vehicleDurationLabel(value: VehicleRecord, now = new Date()) {
  return occurrenceDurationLabel(vehicleOccurrence(value), now);
}

function parseVehicleRow(value: unknown): VehicleRecord | null {
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
    !vehicleDatePrecisions.includes(
      value.date_precision as VehicleDatePrecision,
    ) ||
    !nullableString(value.occurred_label) ||
    !nullableString(value.occurred_timezone) ||
    typeof value.revision !== "number" ||
    typeof value.updated_at !== "string" ||
    !nullableString(value.make) ||
    !nullableString(value.model) ||
    !nullableInteger(value.model_year) ||
    !nullableString(value.color) ||
    !nullableString(value.timeline_track_id) ||
    !nullableString(value.timeline_track_name) ||
    !stringArray(value.collection_names) ||
    !stringArray(value.tag_names) ||
    typeof value.total_count !== "number"
  ) {
    return null;
  }

  const attachments = parseAttachments(value.attachments);
  if (!attachments) return null;

  return {
    attachments,
    body: value.body,
    collectionNames: value.collection_names,
    color: value.color,
    datePrecision: value.date_precision as VehicleDatePrecision,
    id: value.entry_id,
    make: value.make,
    model: value.model,
    modelYear: value.model_year,
    occurredEnd: value.occurred_end,
    occurredLabel: value.occurred_label,
    occurredStart: value.occurred_start,
    occurredTimezone: value.occurred_timezone ?? "UTC",
    revision: value.revision,
    tagNames: value.tag_names,
    timelineTrackId: value.timeline_track_id,
    timelineTrackName: value.timeline_track_name,
    title: value.title,
    totalCount: value.total_count,
    updatedAt: value.updated_at,
  };
}

function parseAttachments(value: unknown): VehicleAttachment[] | null {
  if (!Array.isArray(value)) return null;
  const attachments: VehicleAttachment[] = [];

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

function nullableString(value: unknown) {
  return value === null || typeof value === "string";
}

function nullableNumber(value: unknown): value is number | null {
  return (
    value === null || (typeof value === "number" && Number.isFinite(value))
  );
}

function nullableInteger(value: unknown): value is number | null {
  return (
    value === null || (typeof value === "number" && Number.isSafeInteger(value))
  );
}

function stringArray(value: unknown): value is string[] {
  return (
    Array.isArray(value) && value.every((item) => typeof item === "string")
  );
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}
