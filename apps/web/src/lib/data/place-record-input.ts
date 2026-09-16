export const placeAddressLimit = 500;
export const placeCityLimit = 200;
export const placeCountryLimit = 200;
export const placeNameLimit = 200;
export const placeNotesLimit = 10_000;
export const placeRegionLimit = 200;
export const placeRelatedEntryLimit = 100;

export type PlaceRecordInput = {
  address: string | null;
  city: string | null;
  country: string | null;
  id: string | null;
  latitude: number | null;
  longitude: number | null;
  name: string;
  notes: string | null;
  region: string | null;
  relatedEntryIds: string[];
  revision: number | null;
};

type Parsed<T> =
  { data: T; success: true } | { message: string; success: false };

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function parsePlaceRecordInput(
  input: unknown,
): Parsed<PlaceRecordInput> {
  if (!isRecord(input))
    return invalid("This Place is invalid. Refresh and try again.");

  const name = normalizedString(input.name);
  const address = optionalString(input.address);
  const city = optionalString(input.city);
  const region = optionalString(input.region);
  const country = optionalString(input.country);
  const notes = optionalString(input.notes);
  const relatedEntryIds = normalizedUuidArray(input.relatedEntryIds);

  if (!name) return invalid("Add a name for this Place.");
  if (name.length > placeNameLimit) {
    return invalid(`Place names can be up to ${placeNameLimit} characters.`);
  }
  if ((address?.length ?? 0) > placeAddressLimit) {
    return invalid(`Addresses can be up to ${placeAddressLimit} characters.`);
  }
  if ((city?.length ?? 0) > placeCityLimit) {
    return invalid(`Cities can be up to ${placeCityLimit} characters.`);
  }
  if ((region?.length ?? 0) > placeRegionLimit) {
    return invalid(`Regions can be up to ${placeRegionLimit} characters.`);
  }
  if ((country?.length ?? 0) > placeCountryLimit) {
    return invalid(`Countries can be up to ${placeCountryLimit} characters.`);
  }
  if ((notes?.length ?? 0) > placeNotesLimit) {
    return invalid(`Notes can be up to ${placeNotesLimit} characters.`);
  }
  if (!relatedEntryIds || relatedEntryIds.length > placeRelatedEntryLimit) {
    return invalid(`Relate up to ${placeRelatedEntryLimit} Items.`);
  }
  if (!isPlaceIdentity(input.id, input.revision)) {
    return invalid("This Place version is invalid. Refresh and try again.");
  }

  const latitude = nullableCoordinate(input.latitude, -90, 90);
  const longitude = nullableCoordinate(input.longitude, -180, 180);
  if (
    latitude === undefined ||
    longitude === undefined ||
    (latitude === null) !== (longitude === null)
  ) {
    return invalid(
      "Add both valid latitude and longitude values, or leave both empty.",
    );
  }

  return {
    data: {
      address,
      city,
      country,
      id: input.id as string | null,
      latitude,
      longitude,
      name,
      notes,
      region,
      relatedEntryIds,
      revision: input.revision as number | null,
    },
    success: true,
  };
}

export function isPlaceIdentity(id: unknown, revision: unknown) {
  return id === null
    ? revision === null
    : validUuid(id) &&
        typeof revision === "number" &&
        Number.isSafeInteger(revision) &&
        revision >= 1;
}

function nullableCoordinate(
  value: unknown,
  minimum: number,
  maximum: number,
): number | null | undefined {
  if (value === null || value === undefined || value === "") return null;
  if (typeof value !== "number" || !Number.isFinite(value)) return undefined;
  return value >= minimum && value <= maximum ? value : undefined;
}

function normalizedUuidArray(value: unknown) {
  if (!Array.isArray(value)) return null;
  const unique = new Set<string>();
  for (const item of value) {
    if (!validUuid(item)) return null;
    unique.add(item.toLocaleLowerCase());
  }
  return [...unique];
}

function validUuid(value: unknown): value is string {
  return typeof value === "string" && uuidPattern.test(value);
}

function normalizedString(value: unknown) {
  return typeof value === "string" ? value.trim() : "";
}

function optionalString(value: unknown) {
  const normalized = normalizedString(value);
  return normalized || null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function invalid(message: string) {
  return { message, success: false } as const;
}
