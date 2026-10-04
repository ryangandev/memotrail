import { validateOccurrence } from "./occurrence";
import { tagNamesLimitMessage } from "./organization";
import { parseTagNames } from "./inbox-review";

export const homeBodyLimit = 50_000;
export const homeLabelLimit = 200;
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
  body: string;
  datePrecision: HomeDatePrecision;
  id: string | null;
  moveInReason: string | null;
  moveOutReason: string | null;
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

export function parseHomeEntryInput(input: unknown): Parsed<HomeEntryInput> {
  if (!isRecord(input)) {
    return invalid("This Home is invalid. Refresh and try again.");
  }

  const title = normalizedString(input.title);
  const body = normalizedString(input.body);
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

  if (exceeds(moveInReason, 10_000) || exceeds(moveOutReason, 10_000)) {
    return invalid("One of this Home's move details is too long.");
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

  if (!tagNames) {
    return invalid(tagNamesLimitMessage);
  }

  if (!isHomeEntryIdentity(input.id, input.revision)) {
    return invalid("This Home version is invalid. Refresh and try again.");
  }

  return {
    data: {
      body,
      datePrecision: input.datePrecision as HomeDatePrecision,
      id: input.id as string | null,
      moveInReason,
      moveOutReason,
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
