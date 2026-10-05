import { tagNamesLimitMessage } from "./organization";
import { parseTagNames } from "./inbox-review";
import {
  occurrencePrecisions,
  validTimezone,
  validateOccurrence,
} from "./occurrence";

export const goalBodyLimit = 50_000;
export const goalLabelLimit = 200;
export const goalTitleLimit = 200;

export const goalStatuses = ["active", "achieved", "let_go"] as const;
export const goalAchievementPrecisions = occurrencePrecisions;

export type GoalStatus = (typeof goalStatuses)[number];
export type GoalAchievementPrecision =
  (typeof goalAchievementPrecisions)[number];

export type GoalEntryInput = {
  body: string;
  id: string | null;
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
  occurredStart: string | null;
  occurredEnd?: string | null;
  occurredTimezone: string;
  revision: number;
};

export type GoalExtractionInput = Pick<
  GoalEntryInput,
  "title" | "targetDate"
> & {
  goalId: string;
  sourceId: string;
  sourceRevision: number;
};

export function parseGoalExtractionInput(
  input: unknown,
): Parsed<GoalExtractionInput> {
  if (
    !isRecord(input) ||
    !validUuid(input.goalId) ||
    !validUuid(input.sourceId) ||
    typeof input.sourceRevision !== "number" ||
    !Number.isSafeInteger(input.sourceRevision) ||
    input.sourceRevision < 1
  )
    return invalid("Choose a current Wiki Item to add to Someday.");
  const parsed = parseGoalEntryInput({
    ...input,
    body: "",
    id: null,
    revision: null,
    status: "active",
    tagNames: [],
  });
  if (!parsed.success) return parsed;
  const { title, targetDate } = parsed.data;
  return {
    success: true,
    data: {
      goalId: input.goalId,
      sourceId: input.sourceId,
      sourceRevision: input.sourceRevision,
      title,
      targetDate,
    },
  };
}

type Parsed<T> =
  { data: T; success: true } | { message: string; success: false };

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function parseGoalEntryInput(input: unknown): Parsed<GoalEntryInput> {
  if (!isRecord(input)) {
    return invalid("This item is invalid. Refresh and try again.");
  }

  const title = normalizedString(input.title);
  const body = normalizedString(input.body);
  const tagNames = parseTagNames(input.tagNames);

  if (!title) return invalid("Add a title.");
  if (title.length > goalTitleLimit) {
    return invalid(`Titles can be up to ${goalTitleLimit} characters.`);
  }
  if (body.length > goalBodyLimit) {
    return invalid(`Notes can be up to ${goalBodyLimit} characters.`);
  }
  if (
    typeof input.status !== "string" ||
    !goalStatuses.includes(input.status as GoalStatus)
  ) {
    return invalid("Choose a valid status.");
  }
  if (!tagNames) {
    return invalid(tagNamesLimitMessage);
  }
  if (!isGoalEntryIdentity(input.id, input.revision)) {
    return invalid("This version is invalid. Refresh and try again.");
  }

  const targetDate = optionalCalendarDate(input.targetDate);
  if (targetDate === undefined) {
    return invalid("Choose a valid target date or leave it empty.");
  }

  return {
    data: {
      body,
      id: input.id as string | null,
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
    return invalid("This version is invalid. Refresh and try again.");
  }
  if (input.id === null || input.revision === null) {
    return invalid("Save this item before marking it done.");
  }

  const occurredTimezone = normalizedString(input.occurredTimezone);
  if (!validTimezone(occurredTimezone)) {
    return invalid("Choose a valid occurrence time zone.");
  }
  if (
    !goalAchievementPrecisions.includes(
      input.datePrecision as GoalAchievementPrecision,
    )
  ) {
    return invalid("Choose a valid date precision.");
  }
  const datePrecision = input.datePrecision as GoalAchievementPrecision;
  const occurredLabel = normalizedString(input.occurredLabel) || null;
  if (occurredLabel && occurredLabel.length > goalLabelLimit) {
    return invalid(
      `Human date labels can be up to ${goalLabelLimit} characters.`,
    );
  }
  const occurredStart = optionalInstant(input.occurredStart);
  const occurredEnd = optionalInstant(input.occurredEnd);
  if (occurredStart === undefined) {
    return invalid("Choose a valid date or leave it empty.");
  }
  if (occurredEnd === undefined) return invalid("Choose a valid end date.");
  const occurrenceError = validateOccurrence({
    datePrecision,
    occurredAt: occurredStart,
    occurredEnd,
    occurredLabel,
    occurredTimezone,
  });
  if (occurrenceError) return invalid(occurrenceError);

  return {
    data: {
      datePrecision,
      id: input.id as string,
      occurredLabel,
      occurredStart,
      occurredEnd,
      occurredTimezone,
      revision: input.revision as number,
    },
    success: true,
  };
}

// An ISO instant, kept as sent when it has more than millisecond precision.
function optionalInstant(value: unknown): string | null | undefined {
  if (value === null || value === undefined || value === "") return null;
  if (
    typeof value !== "string" ||
    !/^\d{4}-\d{2}-\d{2}T/.test(value) ||
    value.startsWith("0000-")
  )
    return undefined;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return undefined;
  const day = new Date(`${value.slice(0, 10)}T12:00:00Z`);
  if (
    !Number.isFinite(day.getTime()) ||
    day.toISOString().slice(0, 10) !== value.slice(0, 10)
  )
    return undefined;
  // Do not round a database instant to JavaScript's millisecond precision.
  return /\.\d{4,}(Z|[+-]\d{2}:\d{2})$/.test(value)
    ? value
    : date.toISOString();
}

export function isGoalEntryIdentity(id: unknown, revision: unknown) {
  return id === null
    ? revision === null
    : validUuid(id) &&
        typeof revision === "number" &&
        Number.isSafeInteger(revision) &&
        revision >= 1;
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

function validUuid(value: unknown): value is string {
  return typeof value === "string" && uuidPattern.test(value);
}

function normalizedString(value: unknown) {
  return typeof value === "string" ? value.trim() : "";
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function invalid(message: string) {
  return { message, success: false } as const;
}
