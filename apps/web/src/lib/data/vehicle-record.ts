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
  occurredStart: string;
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

export function vehicleRangeLabel(vehicle: VehicleRecord) {
  if (vehicle.occurredLabel) return vehicle.occurredLabel;
  const start = formatVehicleDate(
    vehicle.occurredStart,
    vehicle.datePrecision,
    vehicle.occurredTimezone,
  );
  if (!vehicle.occurredEnd) return `Since ${start}`;
  return `${start} - ${formatVehicleDate(
    vehicle.occurredEnd,
    vehicle.datePrecision,
    vehicle.occurredTimezone,
  )}`;
}

export function vehicleDurationLabel(vehicle: VehicleRecord, now = new Date()) {
  const start = calendarParts(vehicle.occurredStart, vehicle.occurredTimezone);
  const end = calendarParts(
    vehicle.occurredEnd ?? now.toISOString(),
    vehicle.occurredTimezone,
  );
  if (!start || !end) return "Duration unavailable";

  let months = (end.year - start.year) * 12 + end.month - start.month;
  if (end.day < start.day) months -= 1;
  months = Math.max(0, months);
  if (months === 0) return "Less than a month";

  const years = Math.floor(months / 12);
  const remainingMonths = months % 12;
  const parts: string[] = [];
  if (years > 0) parts.push(`${years} ${years === 1 ? "year" : "years"}`);
  if (remainingMonths > 0) {
    parts.push(
      `${remainingMonths} ${remainingMonths === 1 ? "month" : "months"}`,
    );
  }
  return parts.join(" ");
}

function parseVehicleRow(value: unknown): VehicleRecord | null {
  if (
    !isRecord(value) ||
    typeof value.entry_id !== "string" ||
    typeof value.title !== "string" ||
    typeof value.body !== "string" ||
    typeof value.occurred_start !== "string" ||
    !nullableString(value.occurred_end) ||
    typeof value.date_precision !== "string" ||
    !vehicleDatePrecisions.includes(
      value.date_precision as VehicleDatePrecision,
    ) ||
    !nullableString(value.occurred_label) ||
    typeof value.occurred_timezone !== "string" ||
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
    occurredTimezone: value.occurred_timezone,
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

function formatVehicleDate(
  value: string,
  precision: VehicleDatePrecision,
  timeZone: string,
) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "Date unavailable";
  const options: Intl.DateTimeFormatOptions =
    precision === "year"
      ? { year: "numeric" }
      : precision === "month" ||
          precision === "approximate" ||
          precision === "age" ||
          precision === "range"
        ? { month: "short", year: "numeric" }
        : { day: "numeric", month: "short", year: "numeric" };

  try {
    return new Intl.DateTimeFormat("en", { ...options, timeZone }).format(date);
  } catch {
    return new Intl.DateTimeFormat("en", {
      ...options,
      timeZone: "UTC",
    }).format(date);
  }
}

function calendarParts(value: string, timeZone: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return null;
  try {
    const parts = new Intl.DateTimeFormat("en-CA", {
      day: "numeric",
      month: "numeric",
      timeZone,
      year: "numeric",
    }).formatToParts(date);
    const values = Object.fromEntries(
      parts
        .filter((part) => part.type !== "literal")
        .map((part) => [part.type, Number(part.value)]),
    );
    return { day: values.day, month: values.month, year: values.year };
  } catch {
    return calendarParts(value, "UTC");
  }
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
