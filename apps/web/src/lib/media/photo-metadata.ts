import type { OccurrenceDraft } from "@/lib/data/occurrence";

export type PhotoMetadata = {
  capturedLocal: string | null;
  calendarDate: string | null;
  offset: string | null;
  latitude: number | null;
  longitude: number | null;
};
export type EntryPhoto = { id: string; name: string; imageUrl: string | null };
export type PhotoMetadataResponse = PhotoMetadata & {
  attachmentId: string;
  sourceVersion: string;
};

/** Camera wall-clock values are never interpreted in the server's or browser's timezone. */
export function normalizePhotoMetadata(
  tags: Record<string, unknown>,
): PhotoMetadata {
  let capturedLocal: string | null = null;
  const raw =
    typeof tags.DateTimeOriginal === "string"
      ? tags.DateTimeOriginal.trim()
      : "";
  const match = /^(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})$/.exec(raw);
  if (match) {
    const local = `${match[1]}-${match[2]}-${match[3]}T${match[4]}:${match[5]}:${match[6]}`;
    const date = new Date(`${local}Z`);
    if (
      +match[1] > 0 &&
      Number.isFinite(date.getTime()) &&
      date.toISOString().slice(0, 19) === local
    ) {
      const fraction =
        typeof tags.SubSecTimeOriginal === "string" &&
        /^\d{1,9}$/.test(tags.SubSecTimeOriginal)
          ? `.${tags.SubSecTimeOriginal}`
          : "";
      capturedLocal = local + fraction;
    }
  }
  const rawOffset =
    typeof tags.OffsetTimeOriginal === "string"
      ? tags.OffsetTimeOriginal.trim()
      : "";
  const offsetMatch = /^([+-])(\d{2}):(\d{2})$/.exec(rawOffset);
  const offset =
    offsetMatch &&
    +offsetMatch[2] <= 14 &&
    +offsetMatch[3] < 60 &&
    (+offsetMatch[2] !== 14 || +offsetMatch[3] === 0)
      ? rawOffset
      : null;
  const coordinates = (
    values: unknown,
    reference: unknown,
    limit: number,
    positive: string,
    negative: string,
  ) => {
    if (
      !Array.isArray(values) ||
      values.length !== 3 ||
      !values.every(
        (v) => typeof v === "number" && Number.isFinite(v) && v >= 0,
      ) ||
      ![positive, negative].includes(reference as string)
    )
      return null;
    if (values[1] >= 60 || values[2] >= 60) return null;
    const value = values[0] + values[1] / 60 + values[2] / 3600;
    return value <= limit ? value * (reference === negative ? -1 : 1) : null;
  };
  const latitude = coordinates(
    tags.GPSLatitude,
    tags.GPSLatitudeRef,
    90,
    "N",
    "S",
  );
  const longitude = coordinates(
    tags.GPSLongitude,
    tags.GPSLongitudeRef,
    180,
    "E",
    "W",
  );
  return {
    capturedLocal,
    calendarDate: capturedLocal?.slice(0, 10) ?? null,
    offset: capturedLocal ? offset : null,
    latitude: latitude !== null && longitude !== null ? latitude : null,
    longitude: latitude !== null && longitude !== null ? longitude : null,
  };
}

export function photoCalendarDateDraft(
  date: string,
  previous: OccurrenceDraft,
): OccurrenceDraft {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(date);
  if (
    !match ||
    !normalizePhotoMetadata({
      DateTimeOriginal: `${match[1]}:${match[2]}:${match[3]} 12:00:00`,
    }).calendarDate
  )
    throw new Error("Invalid camera date");
  return {
    precision: "day",
    start: date,
    end: "",
    label: "",
    timezone: previous.timezone,
  };
}
