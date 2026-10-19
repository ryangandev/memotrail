export type ExistingLocation = {
  kind: "existing";
  id: string;
  revision: number;
  formattedAddress: string | null;
  address: string | null;
  city: string | null;
  region: string | null;
  postalCode: string | null;
  country: string | null;
  countryCode: string | null;
  latitude: number | null;
  longitude: number | null;
  timezone: string | null;
  resultType: string | null;
};

export type ProviderLocation = {
  kind: "provider";
  provider: "geoapify";
  providerLocationId: string;
  formattedAddress: string;
  address: string | null;
  city: string | null;
  region: string | null;
  postalCode: string | null;
  country: string | null;
  countryCode: string | null;
  latitude: number;
  longitude: number;
  timezone: string | null;
  resultType: string | null;
  confidence: number | null;
  matchType: string | null;
  dataSource: string | null;
};

export type LocationSelection = ExistingLocation | ProviderLocation;

/** An address typed by hand. It has no coordinates. */
export type ManualLocation = {
  kind: "manual";
  address: string | null;
  city: string | null;
  region: string | null;
  country: string | null;
};

export type LocationInput = LocationSelection | ManualLocation;

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function validLocationSelection(
  value: unknown,
): value is LocationSelection {
  if (!isRecord(value) || !validLocationFields(value)) return false;
  if (value.kind === "existing") {
    return (
      typeof value.id === "string" &&
      uuidPattern.test(value.id) &&
      Number.isInteger(value.revision) &&
      Number(value.revision) > 0
    );
  }
  return (
    value.kind === "provider" &&
    value.provider === "geoapify" &&
    validBoundedString(value.providerLocationId, 500) &&
    validBoundedString(value.formattedAddress, 1000) &&
    typeof value.latitude === "number" &&
    Number.isFinite(value.latitude) &&
    value.latitude >= -90 &&
    value.latitude <= 90 &&
    typeof value.longitude === "number" &&
    Number.isFinite(value.longitude) &&
    value.longitude >= -180 &&
    value.longitude <= 180 &&
    nullableNumber(value.confidence) &&
    (value.confidence === null ||
      (typeof value.confidence === "number" &&
        value.confidence >= 0 &&
        value.confidence <= 1)) &&
    nullableBoundedString(value.matchType, 100) &&
    nullableBoundedString(value.dataSource, 200)
  );
}

export function validLocationInput(value: unknown): value is LocationInput {
  if (isRecord(value) && value.kind === "manual") {
    const parts = [value.address, value.city, value.region, value.country];
    return (
      nullableBoundedString(value.address, 500) &&
      nullableBoundedString(value.city, 200) &&
      nullableBoundedString(value.region, 200) &&
      nullableBoundedString(value.country, 200) &&
      parts.some((part) => typeof part === "string" && part.trim() !== "")
    );
  }
  return validLocationSelection(value);
}

export function existingLocationFromRow(
  value: unknown,
): ExistingLocation | null {
  if (!isRecord(value)) return null;
  const location: ExistingLocation = {
    kind: "existing",
    id: stringValue(value.id) ?? "",
    revision: numberValue(value.revision) ?? 0,
    formattedAddress: nullableStringValue(value.formatted_address),
    address: nullableStringValue(value.address),
    city: nullableStringValue(value.city),
    region: nullableStringValue(value.region),
    postalCode: nullableStringValue(value.postal_code),
    country: nullableStringValue(value.country),
    countryCode: nullableStringValue(value.country_code),
    latitude: nullableNumberValue(value.latitude),
    longitude: nullableNumberValue(value.longitude),
    timezone: nullableStringValue(value.timezone_id),
    resultType: nullableStringValue(value.result_type),
  };
  return validLocationSelection(location) ? location : null;
}

/**
 * Once a save stores the chosen Location, the editor holds that saved snapshot.
 * A later save then keeps it instead of choosing the provider result again.
 */
export function savedLocationSelection(
  selection: LocationSelection | null,
  savedId: string | null,
  savedRevision?: number,
): ExistingLocation | null {
  if (!selection || !savedId) return null;
  if (selection.kind === "existing")
    return {
      ...selection,
      id: savedId,
      revision: savedRevision ?? selection.revision,
    };
  return {
    kind: "existing",
    id: savedId,
    revision: savedRevision ?? 1,
    formattedAddress: selection.formattedAddress,
    address: selection.address,
    city: selection.city,
    region: selection.region,
    postalCode: selection.postalCode,
    country: selection.country,
    countryCode: selection.countryCode,
    latitude: selection.latitude,
    longitude: selection.longitude,
    timezone: selection.timezone,
    resultType: selection.resultType,
  };
}

type LocationLabelFields = {
  formattedAddress: string | null;
  address?: string | null;
  city?: string | null;
  region?: string | null;
  country?: string | null;
  latitude: number | null;
  longitude: number | null;
};

/** A Location from photo GPS has coordinates but no address, so it reads as its coordinates. */
export function locationDisplayLabel(location: LocationLabelFields) {
  return (
    location.formattedAddress ||
    [location.address, location.city, location.region, location.country]
      .filter((part): part is string => Boolean(part))
      .join(", ") ||
    (location.latitude !== null && location.longitude !== null
      ? `${location.latitude.toFixed(5)}, ${location.longitude.toFixed(5)}`
      : "Location not set")
  );
}

function validLocationFields(value: Record<string, unknown>) {
  return (
    nullableBoundedString(value.formattedAddress, 1000) &&
    nullableBoundedString(value.address, 500) &&
    nullableBoundedString(value.city, 200) &&
    nullableBoundedString(value.region, 200) &&
    nullableBoundedString(value.postalCode, 40) &&
    nullableBoundedString(value.country, 200) &&
    nullableBoundedString(value.countryCode, 2) &&
    nullableCoordinate(value.latitude, -90, 90) &&
    nullableCoordinate(value.longitude, -180, 180) &&
    (value.latitude === null) === (value.longitude === null) &&
    nullableBoundedString(value.timezone, 100) &&
    nullableBoundedString(value.resultType, 100)
  );
}

function validBoundedString(value: unknown, limit: number) {
  return (
    typeof value === "string" &&
    value.trim().length > 0 &&
    value.length <= limit
  );
}

function nullableBoundedString(value: unknown, limit: number) {
  return value === null || (typeof value === "string" && value.length <= limit);
}

function nullableCoordinate(value: unknown, minimum: number, maximum: number) {
  return (
    value === null ||
    (typeof value === "number" &&
      Number.isFinite(value) &&
      value >= minimum &&
      value <= maximum)
  );
}

function nullableNumber(value: unknown) {
  return (
    value === null || (typeof value === "number" && Number.isFinite(value))
  );
}

function nullableStringValue(value: unknown) {
  return value === null || value === undefined
    ? null
    : typeof value === "string"
      ? value
      : null;
}

function nullableNumberValue(value: unknown) {
  return value === null || value === undefined
    ? null
    : typeof value === "number" && Number.isFinite(value)
      ? value
      : null;
}

function stringValue(value: unknown) {
  return typeof value === "string" ? value : null;
}

function numberValue(value: unknown) {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}
