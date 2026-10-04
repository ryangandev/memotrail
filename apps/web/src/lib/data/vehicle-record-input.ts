import { validateOccurrence } from "./occurrence";
import { tagNamesLimitMessage } from "./organization";
import { parseTagNames } from "./inbox-review";

export const vehicleBodyLimit = 50_000;
export const vehicleColorLimit = 80;
export const vehicleLabelLimit = 200;
export const vehicleMakeLimit = 120;
export const vehicleModelLimit = 120;
export const vehicleTitleLimit = 200;

export const vehicleDatePrecisions = [
  "exact",
  "day",
  "month",
  "year",
  "approximate",
  "age",
  "range",
  "unknown",
] as const;

export type VehicleDatePrecision = (typeof vehicleDatePrecisions)[number];

export type VehicleEntryInput = {
  body: string;
  color: string | null;
  datePrecision: VehicleDatePrecision;
  id: string | null;
  make: string | null;
  model: string | null;
  modelYear: number | null;
  occurredEnd: string | null;
  occurredLabel: string | null;
  occurredStart: string | null;
  occurredTimezone: string;
  revision: number | null;
  tagNames: string[];
  title: string;
};

type Parsed<T> =
  { data: T; success: true } | { message: string; success: false };

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function parseVehicleEntryInput(
  input: unknown,
): Parsed<VehicleEntryInput> {
  if (!isRecord(input)) {
    return invalid("This Vehicle is invalid. Refresh and try again.");
  }

  const title = normalizedString(input.title);
  const body = normalizedString(input.body);
  const make = optionalString(input.make);
  const model = optionalString(input.model);
  const color = optionalString(input.color);
  const occurredLabel = optionalString(input.occurredLabel);
  const occurredTimezone = normalizedString(input.occurredTimezone);
  const tagNames = parseTagNames(input.tagNames);

  if (!title) {
    return invalid("Add a name or nickname for this Vehicle.");
  }
  if (title.length > vehicleTitleLimit) {
    return invalid(
      `Vehicle names can be up to ${vehicleTitleLimit} characters.`,
    );
  }
  if (body.length > vehicleBodyLimit) {
    return invalid(`Memories can be up to ${vehicleBodyLimit} characters.`);
  }
  if (
    exceeds(make, vehicleMakeLimit) ||
    exceeds(model, vehicleModelLimit) ||
    exceeds(color, vehicleColorLimit)
  ) {
    return invalid("One of this Vehicle's facts is too long.");
  }
  if (occurredLabel && occurredLabel.length > vehicleLabelLimit) {
    return invalid(
      `Human date labels can be up to ${vehicleLabelLimit} characters.`,
    );
  }
  if (
    typeof input.datePrecision !== "string" ||
    !vehicleDatePrecisions.includes(input.datePrecision as VehicleDatePrecision)
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
      datePrecision: input.datePrecision as VehicleDatePrecision,
    },
    true,
  );
  if (occurrenceError) return invalid(occurrenceError);

  const modelYear = optionalModelYear(input.modelYear);
  if (modelYear === undefined) {
    return invalid("Use a model year from 1886 to 2200, or leave it empty.");
  }
  if (!tagNames) {
    return invalid(tagNamesLimitMessage);
  }
  if (!isVehicleEntryIdentity(input.id, input.revision)) {
    return invalid("This Vehicle version is invalid. Refresh and try again.");
  }

  return {
    data: {
      body,
      color,
      datePrecision: input.datePrecision as VehicleDatePrecision,
      id: input.id as string | null,
      make,
      model,
      modelYear,
      occurredEnd,
      occurredLabel,
      occurredStart,
      occurredTimezone,
      revision: input.revision as number | null,
      tagNames,
      title,
    },
    success: true,
  };
}

export function isVehicleEntryIdentity(id: unknown, revision: unknown) {
  return id === null
    ? revision === null
    : validUuid(id) !== null &&
        typeof revision === "number" &&
        Number.isSafeInteger(revision) &&
        revision >= 1;
}

function optionalModelYear(value: unknown): number | null | undefined {
  if (value === null || value === undefined) return null;
  return typeof value === "number" &&
    Number.isSafeInteger(value) &&
    value >= 1886 &&
    value <= 2200
    ? value
    : undefined;
}

function validUuid(value: unknown) {
  return typeof value === "string" && uuidPattern.test(value) ? value : null;
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
