import { validateOccurrence } from "./occurrence";
import { tagNamesLimitMessage } from "./organization";
import { parseTagNames } from "./inbox-review";

export const homeBodyLimit = 50_000;
export const homeLabelLimit = 200;
export const homePlaceNameLimit = 200;
export const homeTitleLimit = 200;

export const homeDatePrecisions = [
  "exact",
  "day",
  "month",
  "year",
  "approximate",
  "age",
  "range",
  "unknown",
] as const;

export type HomeDatePrecision = (typeof homeDatePrecisions)[number];

export type HomeEntryInput = {
  address: string | null;
  body: string;
  city: string | null;
  country: string | null;
  datePrecision: HomeDatePrecision;
  id: string | null;
  latitude: number | null;
  longitude: number | null;
  moveInReason: string | null;
  moveOutReason: string | null;
  occurredEnd: string | null;
  occurredLabel: string | null;
  occurredStart: string | null;
  occurredTimezone: string;
  placeId: string | null;
  placeName: string;
  placeNotes: string | null;
  region: string | null;
  revision: number | null;
  tagNames: string[];
  title: string;
};

type Parsed<T> =
  { data: T; success: true } | { message: string; success: false };

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function parseHomeEntryInput(input: unknown): Parsed<HomeEntryInput> {
  if (!isRecord(input)) {
    return invalid("This Home is invalid. Refresh and try again.");
  }

  const title = normalizedString(input.title);
  const body = normalizedString(input.body);
  const placeName = normalizedString(input.placeName);
  const address = optionalString(input.address);
  const city = optionalString(input.city);
  const region = optionalString(input.region);
  const country = optionalString(input.country);
  const placeNotes = optionalString(input.placeNotes);
  const moveInReason = optionalString(input.moveInReason);
  const moveOutReason = optionalString(input.moveOutReason);
  const occurredLabel = optionalString(input.occurredLabel);
  const occurredTimezone = normalizedString(input.occurredTimezone);
  const tagNames = parseTagNames(input.tagNames);

  if (!title) {
    return invalid("Add a name for this Home.");
  }

  if (title.length > homeTitleLimit) {
    return invalid(`Home names can be up to ${homeTitleLimit} characters.`);
  }

  if (body.length > homeBodyLimit) {
    return invalid(`Memories can be up to ${homeBodyLimit} characters.`);
  }

  if (placeName.length > homePlaceNameLimit) {
    return invalid(
      `Address labels can be up to ${homePlaceNameLimit} characters.`,
    );
  }

  if (
    exceeds(address, 500) ||
    exceeds(city, 200) ||
    exceeds(region, 200) ||
    exceeds(country, 200) ||
    exceeds(placeNotes, 10_000) ||
    exceeds(moveInReason, 10_000) ||
    exceeds(moveOutReason, 10_000)
  ) {
    return invalid("One of this Home's Location or move details is too long.");
  }

  if (occurredLabel && occurredLabel.length > homeLabelLimit) {
    return invalid(
      `Human date labels can be up to ${homeLabelLimit} characters.`,
    );
  }

  if (
    typeof input.datePrecision !== "string" ||
    !homeDatePrecisions.includes(input.datePrecision as HomeDatePrecision)
  ) {
    return invalid("Choose a valid date precision.");
  }

  const occurredStart = input.occurredStart;
  const occurredEnd = input.occurredEnd;
  if (
    !(occurredStart === null || typeof occurredStart === "string") ||
    !(occurredEnd === null || typeof occurredEnd === "string")
  )
    return invalid("Choose a valid date.");
  const occurrenceError = validateOccurrence(
    {
      occurredAt: occurredStart,
      occurredEnd,
      occurredLabel,
      occurredTimezone,
      datePrecision: input.datePrecision as HomeDatePrecision,
    },
    true,
  );
  if (occurrenceError) return invalid(occurrenceError);
  if (moveOutReason && !occurredEnd)
    return invalid("Add a move-out date before recording why you left.");

  const latitude = optionalCoordinate(input.latitude);
  const longitude = optionalCoordinate(input.longitude);

  if (latitude === undefined || longitude === undefined) {
    return invalid("Coordinates must be valid numbers.");
  }

  if ((latitude === null) !== (longitude === null)) {
    return invalid("Add both latitude and longitude, or leave both empty.");
  }

  if (
    (latitude !== null && (latitude < -90 || latitude > 90)) ||
    (longitude !== null && (longitude < -180 || longitude > 180))
  ) {
    return invalid(
      "Coordinates are outside the valid latitude or longitude range.",
    );
  }

  if (!tagNames) {
    return invalid(tagNamesLimitMessage);
  }

  if (!isHomeEntryIdentity(input.id, input.revision)) {
    return invalid("This Home version is invalid. Refresh and try again.");
  }

  const placeId = input.placeId === null ? null : validUuid(input.placeId);

  if (input.placeId !== null && !placeId) {
    return invalid("This Home's Location changed. Refresh and try again.");
  }

  return {
    data: {
      address,
      body,
      city,
      country,
      datePrecision: input.datePrecision as HomeDatePrecision,
      id: input.id as string | null,
      latitude,
      longitude,
      moveInReason,
      moveOutReason,
      occurredEnd,
      occurredLabel,
      occurredStart,
      occurredTimezone,
      placeId,
      placeName,
      placeNotes,
      region,
      revision: input.revision as number | null,
      tagNames,
      title,
    },
    success: true,
  };
}

export function isHomeEntryIdentity(id: unknown, revision: unknown) {
  return id === null
    ? revision === null
    : validUuid(id) !== null &&
        typeof revision === "number" &&
        Number.isSafeInteger(revision) &&
        revision >= 1;
}

function validUuid(value: unknown) {
  return typeof value === "string" && uuidPattern.test(value) ? value : null;
}

function optionalCoordinate(value: unknown): number | null | undefined {
  if (value === null || value === undefined) {
    return null;
  }

  return typeof value === "number" && Number.isFinite(value)
    ? value
    : undefined;
}

function normalizedString(value: unknown) {
  return typeof value === "string" ? value.trim() : "";
}

function optionalString(value: unknown) {
  const normalized = normalizedString(value);
  return normalized || null;
}

function exceeds(value: string | null, limit: number) {
  return Boolean(value && value.length > limit);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function invalid(message: string) {
  return { message, success: false } as const;
}
