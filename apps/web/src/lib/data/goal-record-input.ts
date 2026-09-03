import { parseOrganizationNames } from "./inbox-review";

export const goalBodyLimit = 50_000;
export const goalLabelLimit = 200;
export const goalRelatedEntryLimit = 100;
export const goalTitleLimit = 200;

export const goalHorizons = ["short_term", "long_term", "someday"] as const;
export const goalStatuses = [
  "considering",
  "active",
  "paused",
  "achieved",
  "let_go",
] as const;
export const goalAchievementPrecisions = [
  "exact",
  "day",
  "month",
  "year",
  "approximate",
  "age",
] as const;

export type GoalHorizon = (typeof goalHorizons)[number];
export type GoalStatus = (typeof goalStatuses)[number];
export type GoalAchievementPrecision =
  (typeof goalAchievementPrecisions)[number];

export type GoalEntryInput = {
  body: string;
  collectionNames: string[];
  horizon: GoalHorizon;
  id: string | null;
  relatedEntryIds: string[];
  revision: number | null;
  status: GoalStatus;
  tagNames: string[];
  targetDate: string | null;
  title: string;
};

export type GoalAchievementInput = {
  datePrecision: GoalAchievementPrecision;
  id: string;
  occurredLabel: string | null;
  occurredStart: string;
  occurredTimezone: string;
  revision: number;
};

type Parsed<T> =
  { data: T; success: true } | { message: string; success: false };

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function parseGoalEntryInput(input: unknown): Parsed<GoalEntryInput> {
  if (!isRecord(input)) {
    return invalid("This Goal is invalid. Refresh and try again.");
  }

  const title = normalizedString(input.title);
  const body = normalizedString(input.body);
  const collectionNames = parseOrganizationNames(input.collectionNames, 20, 80);
  const tagNames = parseOrganizationNames(input.tagNames, 50, 60);
  const relatedEntryIds = normalizedUuidArray(input.relatedEntryIds);

  if (!title) return invalid("Add a title for this Goal.");
  if (title.length > goalTitleLimit) {
    return invalid(`Goal titles can be up to ${goalTitleLimit} characters.`);
  }
  if (body.length > goalBodyLimit) {
    return invalid(`Reflections can be up to ${goalBodyLimit} characters.`);
  }
  if (
    typeof input.horizon !== "string" ||
    !goalHorizons.includes(input.horizon as GoalHorizon)
  ) {
    return invalid("Choose a valid Goal horizon.");
  }
  if (
    typeof input.status !== "string" ||
    !goalStatuses.includes(input.status as GoalStatus)
  ) {
    return invalid("Choose a valid reflective state.");
  }
  if (!collectionNames) {
    return invalid("Use up to 20 Collections with names under 80 characters.");
  }
  if (!tagNames) {
    return invalid("Use up to 50 tags with names under 60 characters.");
  }
  if (!relatedEntryIds || relatedEntryIds.length > goalRelatedEntryLimit) {
    return invalid(`Relate up to ${goalRelatedEntryLimit} Entries.`);
  }
  if (!isGoalEntryIdentity(input.id, input.revision)) {
    return invalid("This Goal version is invalid. Refresh and try again.");
  }

  const targetDate = optionalCalendarDate(input.targetDate);
  if (targetDate === undefined) {
    return invalid("Choose a valid target date or leave it empty.");
  }

  return {
    data: {
      body,
      collectionNames,
      horizon: input.horizon as GoalHorizon,
      id: input.id as string | null,
      relatedEntryIds,
      revision: input.revision as number | null,
      status: input.status as GoalStatus,
      tagNames,
      targetDate,
      title,
    },
    success: true,
  };
}

export function parseGoalAchievementInput(
  input: unknown,
): Parsed<GoalAchievementInput> {
  if (!isRecord(input) || !isGoalEntryIdentity(input.id, input.revision)) {
    return invalid("This Goal version is invalid. Refresh and try again.");
  }
  if (input.id === null || input.revision === null) {
    return invalid("Save this Goal before recording its achievement.");
  }

  const occurredStart = validIsoDate(input.occurredStart);
  const occurredTimezone = normalizedString(input.occurredTimezone);
  const occurredLabel = optionalString(input.occurredLabel);
  if (!occurredStart) return invalid("Choose when you achieved this Goal.");
  if (!occurredTimezone || occurredTimezone.length > 100) {
    return invalid("Choose a valid occurrence time zone.");
  }
  if (
    typeof input.datePrecision !== "string" ||
    !goalAchievementPrecisions.includes(
      input.datePrecision as GoalAchievementPrecision,
    )
  ) {
    return invalid("Choose a valid achievement date precision.");
  }
  if (occurredLabel && occurredLabel.length > goalLabelLimit) {
    return invalid(
      `Human date labels can be up to ${goalLabelLimit} characters.`,
    );
  }

  return {
    data: {
      datePrecision: input.datePrecision as GoalAchievementPrecision,
      id: input.id as string,
      occurredLabel,
      occurredStart,
      occurredTimezone,
      revision: input.revision as number,
    },
    success: true,
  };
}

export function isGoalEntryIdentity(id: unknown, revision: unknown) {
  return id === null
    ? revision === null
    : validUuid(id) &&
        typeof revision === "number" &&
        Number.isSafeInteger(revision) &&
        revision >= 1;
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

function optionalCalendarDate(value: unknown): string | null | undefined {
  if (value === null || value === undefined || value === "") return null;
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    return undefined;
  }
  const [year, month, day] = value.split("-").map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  return date.getUTCFullYear() === year &&
    date.getUTCMonth() === month - 1 &&
    date.getUTCDate() === day
    ? value
    : undefined;
}

function validIsoDate(value: unknown) {
  if (typeof value !== "string" || !value) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
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
