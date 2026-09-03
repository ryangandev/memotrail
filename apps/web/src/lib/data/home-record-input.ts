import { parseOrganizationNames } from "./inbox-review";

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
] as const;

export type HomeDatePrecision = (typeof homeDatePrecisions)[number];

export type HomeEntryInput = {
  address: string | null;
  body: string;
  city: string | null;
  collectionNames: string[];
  country: string | null;
  datePrecision: HomeDatePrecision;
  id: string | null;
  latitude: number | null;
  longitude: number | null;
  moveInReason: string | null;
  moveOutReason: string | null;
  occurredEnd: string | null;
  occurredLabel: string | null;
  occurredStart: string;
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
  const collectionNames = parseOrganizationNames(input.collectionNames, 20, 80);
  const tagNames = parseOrganizationNames(input.tagNames, 50, 60);

  if (!title) {
    return invalid("Add a name for this Home.");
  }

  if (title.length > homeTitleLimit) {
    return invalid(`Home names can be up to ${homeTitleLimit} characters.`);
  }

  if (body.length > homeBodyLimit) {
    return invalid(`Memories can be up to ${homeBodyLimit} characters.`);
  }

  if (!placeName) {
    return invalid("Add a Place name for this Home.");
  }

  if (placeName.length > homePlaceNameLimit) {
    return invalid(
      `Place names can be up to ${homePlaceNameLimit} characters.`,
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
    return invalid("One of this Home's Place or move details is too long.");
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

  const occurredStart = validIsoDate(input.occurredStart);
  const occurredEnd = input.occurredEnd
    ? validIsoDate(input.occurredEnd)
    : null;

  if (!occurredStart) {
    return invalid("Add the best-known move-in date.");
  }

  if (input.occurredEnd && !occurredEnd) {
    return invalid("Choose a valid move-out date.");
  }

  if (occurredEnd && occurredEnd < occurredStart) {
    return invalid("The move-out date must be on or after the move-in date.");
  }

  if (moveOutReason && !occurredEnd) {
    return invalid("Add a move-out date before recording why you left.");
  }

  if (!occurredTimezone || occurredTimezone.length > 100) {
    return invalid("Choose a valid occurrence time zone.");
  }

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

  if (!collectionNames) {
    return invalid("Use up to 20 Collections with names under 80 characters.");
  }

  if (!tagNames) {
    return invalid("Use up to 50 tags with names under 60 characters.");
  }

  if (!isHomeEntryIdentity(input.id, input.revision)) {
    return invalid("This Home version is invalid. Refresh and try again.");
  }

  const placeId = input.placeId === null ? null : validUuid(input.placeId);

  if (input.placeId !== null && !placeId) {
    return invalid("Choose a valid saved Place or create a new one.");
  }

  return {
    data: {
      address,
      body,
      city,
      collectionNames,
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

function validIsoDate(value: unknown) {
  if (typeof value !== "string" || !value) {
    return null;
  }

  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
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
