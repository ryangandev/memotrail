export const timelineBodyLimit = 50_000;
export const timelineLabelLimit = 200;
export const timelineTitleLimit = 200;

export const timelineDatePrecisions = [
  "exact",
  "day",
  "month",
  "year",
  "approximate",
  "age",
  "range",
  "unknown",
] as const;

export type TimelineDatePrecision = (typeof timelineDatePrecisions)[number];
export type TimelineKind = "event" | "stage";

export type TimelineEntryInput = {
  body: string;
  datePrecision: TimelineDatePrecision;
  id: string | null;
  kind: TimelineKind;
  occurredEnd: string | null;
  occurredLabel: string | null;
  occurredStart: string;
  occurredTimezone: string;
  revision: number | null;
  title: string;
  trackId: string;
};

export type ParsedTimelineEntryInput =
  | { data: TimelineEntryInput; success: true }
  | { message: string; success: false };

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function parseTimelineEntryInput(
  input: TimelineEntryInput,
): ParsedTimelineEntryInput {
  const title = input.title.trim();
  const body = input.body.trim();
  const occurredLabel = input.occurredLabel?.trim() || null;
  const occurredTimezone = input.occurredTimezone.trim();

  if (!uuidPattern.test(input.trackId)) {
    return invalid("Choose a valid Timeline track.");
  }

  if (!title) {
    return invalid("Add a title for this Timeline moment.");
  }

  if (title.length > timelineTitleLimit) {
    return invalid(`Titles can be up to ${timelineTitleLimit} characters.`);
  }

  if (body.length > timelineBodyLimit) {
    return invalid(`Notes can be up to ${timelineBodyLimit} characters.`);
  }

  if (occurredLabel && occurredLabel.length > timelineLabelLimit) {
    return invalid(
      `Human date labels can be up to ${timelineLabelLimit} characters.`,
    );
  }

  if (input.kind !== "stage" && input.kind !== "event") {
    return invalid("Choose Stage or Event.");
  }

  if (!timelineDatePrecisions.includes(input.datePrecision)) {
    return invalid("Choose a valid date precision.");
  }

  const occurredStart = validIsoDate(input.occurredStart);

  if (!occurredStart) {
    return invalid("Choose a valid start date.");
  }

  const occurredEnd = input.occurredEnd
    ? validIsoDate(input.occurredEnd)
    : null;

  if (input.occurredEnd && !occurredEnd) {
    return invalid("Choose a valid end date.");
  }

  if (input.kind === "event" && occurredEnd) {
    return invalid("Events happen at one point and cannot have an end date.");
  }

  if (occurredEnd && occurredEnd < occurredStart) {
    return invalid("The end date must be on or after the start date.");
  }

  if (!occurredTimezone || occurredTimezone.length > 100) {
    return invalid("Choose a valid occurrence time zone.");
  }

  if (!isTimelineEntryIdentity(input.id, input.revision)) {
    return invalid("This Timeline version is invalid. Refresh and try again.");
  }

  return {
    data: {
      ...input,
      body,
      occurredEnd,
      occurredLabel,
      occurredStart,
      occurredTimezone,
      title,
    },
    success: true,
  };
}

export function isTimelineEntryIdentity(
  id: string | null,
  revision: number | null,
) {
  return id === null
    ? revision === null
    : uuidPattern.test(id) &&
        Number.isSafeInteger(revision) &&
        (revision ?? 0) >= 1;
}

export function localDateToISOString(
  value: string,
  timeZone = Intl.DateTimeFormat().resolvedOptions().timeZone,
) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    return null;
  }

  const [year, month, day] = value.split("-").map(Number);
  const calendarDate = new Date(Date.UTC(year, month - 1, day, 12));

  if (
    calendarDate.getUTCFullYear() !== year ||
    calendarDate.getUTCMonth() + 1 !== month ||
    calendarDate.getUTCDate() !== day
  ) {
    return null;
  }

  try {
    const desiredNoon = Date.UTC(year, month - 1, day, 12);
    const zonedParts = dateParts(new Date(desiredNoon), timeZone, true);
    const representedAsUtc = Date.UTC(
      zonedParts.year,
      zonedParts.month - 1,
      zonedParts.day,
      zonedParts.hour,
    );
    const firstPass = desiredNoon - (representedAsUtc - desiredNoon);
    const correctedParts = dateParts(new Date(firstPass), timeZone, true);
    const correctedAsUtc = Date.UTC(
      correctedParts.year,
      correctedParts.month - 1,
      correctedParts.day,
      correctedParts.hour,
    );

    return new Date(firstPass - (correctedAsUtc - desiredNoon)).toISOString();
  } catch {
    return null;
  }
}

export function localDateValue(isoValue: string, timeZone: string) {
  const date = new Date(isoValue);

  if (Number.isNaN(date.getTime())) {
    return "";
  }

  try {
    const parts = dateParts(date, timeZone);
    return `${parts.year}-${String(parts.month).padStart(2, "0")}-${String(parts.day).padStart(2, "0")}`;
  } catch {
    return date.toISOString().slice(0, 10);
  }
}

function dateParts(date: Date, timeZone: string, includeHour = false) {
  const parts = new Intl.DateTimeFormat("en-US", {
    day: "2-digit",
    hour: includeHour ? "2-digit" : undefined,
    hourCycle: "h23",
    month: "2-digit",
    timeZone,
    year: "numeric",
  }).formatToParts(date);
  const part = (type: Intl.DateTimeFormatPartTypes) =>
    Number(parts.find((item) => item.type === type)?.value ?? 0);

  return {
    day: part("day"),
    hour: includeHour ? part("hour") : 12,
    month: part("month"),
    year: part("year"),
  };
}

function validIsoDate(value: string) {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

function invalid(message: string): ParsedTimelineEntryInput {
  return { message, success: false };
}
