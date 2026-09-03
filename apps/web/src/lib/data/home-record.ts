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
  occurredStart: string;
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

export function homeRangeLabel(home: HomeRecord) {
  if (home.occurredLabel) {
    return home.occurredLabel;
  }

  const start = formatHomeDate(
    home.occurredStart,
    home.datePrecision,
    home.occurredTimezone,
  );

  if (!home.occurredEnd) {
    return `Since ${start}`;
  }

  return `${start} - ${formatHomeDate(
    home.occurredEnd,
    home.datePrecision,
    home.occurredTimezone,
  )}`;
}

export function homeDurationLabel(home: HomeRecord, now = new Date()) {
  const start = calendarParts(home.occurredStart, home.occurredTimezone);
  const end = calendarParts(
    home.occurredEnd ?? now.toISOString(),
    home.occurredTimezone,
  );

  if (!start || !end) {
    return "Duration unavailable";
  }

  let months = (end.year - start.year) * 12 + end.month - start.month;
  if (end.day < start.day) {
    months -= 1;
  }
  months = Math.max(0, months);

  if (months === 0) {
    return "Less than a month";
  }

  const years = Math.floor(months / 12);
  const remainingMonths = months % 12;
  const parts: string[] = [];

  if (years > 0) {
    parts.push(`${years} ${years === 1 ? "year" : "years"}`);
  }
  if (remainingMonths > 0) {
    parts.push(
      `${remainingMonths} ${remainingMonths === 1 ? "month" : "months"}`,
    );
  }

  return parts.join(" ");
}

function parseHomeRow(value: unknown): HomeRecord | null {
  if (
    !isRecord(value) ||
    typeof value.entry_id !== "string" ||
    typeof value.title !== "string" ||
    typeof value.body !== "string" ||
    typeof value.occurred_start !== "string" ||
    !nullableString(value.occurred_end) ||
    typeof value.date_precision !== "string" ||
    !homeDatePrecisions.includes(value.date_precision as HomeDatePrecision) ||
    !nullableString(value.occurred_label) ||
    typeof value.occurred_timezone !== "string" ||
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
    occurredTimezone: value.occurred_timezone,
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

function formatHomeDate(
  value: string,
  precision: HomeDatePrecision,
  timeZone: string,
) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return "Date unavailable";
  }

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
  if (Number.isNaN(date.getTime())) {
    return null;
  }

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

    return {
      day: values.day,
      month: values.month,
      year: values.year,
    };
  } catch {
    return calendarParts(value, "UTC");
  }
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
