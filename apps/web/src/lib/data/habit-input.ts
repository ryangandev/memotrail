export const habitNameLimit = 120;
export const habitNoteLimit = 2_000;
export const habitUnitLimit = 40;

export type HabitTrackingMode = "check" | "measure";
export type HabitOccurrenceStatus = "completed" | "missed" | "skipped";
export type HabitCalendarStatus =
  HabitOccurrenceStatus | "not_scheduled" | "pending" | "upcoming";

export type HabitSchedule =
  | { kind: "daily" }
  | { kind: "interval"; every_days: number }
  | { kind: "weekdays"; weekdays: number[] }
  | { kind: "weekly_target"; target: number };

export type HabitInput = {
  endsOn: string | null;
  id: string | null;
  measurementUnit: string;
  name: string;
  revision: number | null;
  schedule: HabitSchedule;
  startsOn: string;
  targetValue: string;
  trackingMode: HabitTrackingMode;
};

export type ParsedHabitInput = Omit<
  HabitInput,
  "measurementUnit" | "name" | "targetValue"
> & {
  measurementUnit: string | null;
  name: string;
  targetValue: number | null;
};

export type HabitOccurrenceInput = {
  expectedRevision: number | null;
  habitId: string;
  localDate: string;
  measuredValue: string;
  note: string;
  status: HabitOccurrenceStatus;
  trackingMode: HabitTrackingMode;
};

export type ParsedHabitOccurrenceInput = Omit<
  HabitOccurrenceInput,
  "measuredValue" | "note"
> & {
  measuredValue: number | null;
  note: string | null;
};

export type ParsedHabitResult =
  | { data: ParsedHabitInput; success: true }
  | { message: string; success: false };

export type ParsedHabitOccurrenceResult =
  | { data: ParsedHabitOccurrenceInput; success: true }
  | { message: string; success: false };

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function parseHabitInput(input: HabitInput): ParsedHabitResult {
  const name = input.name.trim();
  const measurementUnit = input.measurementUnit.trim();

  if (!name) {
    return invalidHabit("Add a name for this Habit.");
  }

  if (name.length > habitNameLimit) {
    return invalidHabit(
      `Habit names can be up to ${habitNameLimit} characters.`,
    );
  }

  if (!isHabitIdentity(input.id, input.revision)) {
    return invalidHabit(
      "This Habit version is invalid. Refresh and try again.",
    );
  }

  if (input.trackingMode !== "check" && input.trackingMode !== "measure") {
    return invalidHabit("Choose Check or Measure.");
  }

  let targetValue: number | null = null;

  if (input.trackingMode === "check") {
    if (measurementUnit || input.targetValue.trim()) {
      return invalidHabit("Check Habits cannot include a measurement target.");
    }
  } else {
    targetValue = positiveNumber(input.targetValue);

    if (!measurementUnit || measurementUnit.length > habitUnitLimit) {
      return invalidHabit(
        `Add a measurement unit up to ${habitUnitLimit} characters.`,
      );
    }

    if (targetValue === null) {
      return invalidHabit("Add a measurement target greater than zero.");
    }
  }

  const schedule = parseHabitSchedule(input.schedule);

  if (!schedule) {
    return invalidHabit("Choose a valid Habit schedule.");
  }

  if (!isLocalDate(input.startsOn)) {
    return invalidHabit("Choose a valid start date.");
  }

  const endsOn = input.endsOn?.trim() || null;

  if (endsOn && !isLocalDate(endsOn)) {
    return invalidHabit("Choose a valid end date.");
  }

  if (endsOn && endsOn < input.startsOn) {
    return invalidHabit("The end date must be on or after the start date.");
  }

  return {
    data: {
      ...input,
      endsOn,
      measurementUnit: measurementUnit || null,
      name,
      schedule,
      targetValue,
    },
    success: true,
  };
}

export function parseHabitOccurrenceInput(
  input: HabitOccurrenceInput,
): ParsedHabitOccurrenceResult {
  if (!uuidPattern.test(input.habitId)) {
    return invalidOccurrence("This Habit reference is invalid.");
  }

  if (!isLocalDate(input.localDate)) {
    return invalidOccurrence("Choose a valid check-in date.");
  }

  if (!Number.isSafeInteger(input.expectedRevision ?? 1)) {
    return invalidOccurrence("This check-in version is invalid.");
  }

  if ((input.expectedRevision ?? 1) < 1) {
    return invalidOccurrence("This check-in version is invalid.");
  }

  if (
    input.status !== "completed" &&
    input.status !== "missed" &&
    input.status !== "skipped"
  ) {
    return invalidOccurrence("Choose a valid check-in status.");
  }

  const note = input.note.trim();

  if (note.length > habitNoteLimit) {
    return invalidOccurrence(
      `Check-in notes can be up to ${habitNoteLimit} characters.`,
    );
  }

  let measuredValue: number | null = null;

  if (input.status === "completed" && input.trackingMode === "measure") {
    measuredValue = nonNegativeNumber(input.measuredValue);

    if (measuredValue === null) {
      return invalidOccurrence("Add a measurement of zero or more.");
    }
  } else if (input.measuredValue.trim()) {
    return invalidOccurrence(
      input.trackingMode === "check"
        ? "Check Habits cannot include a measured value."
        : "Only completed check-ins can include a measured value.",
    );
  }

  return {
    data: {
      ...input,
      measuredValue,
      note: note || null,
    },
    success: true,
  };
}

export function parseHabitSchedule(value: unknown): HabitSchedule | null {
  if (!isRecord(value) || typeof value.kind !== "string") {
    return null;
  }

  if (value.kind === "daily") {
    return { kind: "daily" };
  }

  if (value.kind === "weekdays") {
    if (
      !Array.isArray(value.weekdays) ||
      value.weekdays.length < 1 ||
      value.weekdays.length > 7 ||
      !value.weekdays.every(
        (day) => Number.isSafeInteger(day) && day >= 1 && day <= 7,
      ) ||
      new Set(value.weekdays).size !== value.weekdays.length
    ) {
      return null;
    }

    return { kind: "weekdays", weekdays: [...value.weekdays].sort() };
  }

  if (value.kind === "weekly_target") {
    return Number.isSafeInteger(value.target) &&
      Number(value.target) >= 1 &&
      Number(value.target) <= 7
      ? { kind: "weekly_target", target: Number(value.target) }
      : null;
  }

  if (value.kind === "interval") {
    return Number.isSafeInteger(value.every_days) &&
      Number(value.every_days) >= 1 &&
      Number(value.every_days) <= 365
      ? { kind: "interval", every_days: Number(value.every_days) }
      : null;
  }

  return null;
}

export function isHabitIdentity(id: string | null, revision: number | null) {
  return id === null
    ? revision === null
    : uuidPattern.test(id) &&
        Number.isSafeInteger(revision) &&
        (revision ?? 0) >= 1;
}

export function isLocalDate(value: string) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    return false;
  }

  const [year, month, day] = value.split("-").map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));

  return (
    date.getUTCFullYear() === year &&
    date.getUTCMonth() + 1 === month &&
    date.getUTCDate() === day
  );
}

function positiveNumber(value: string) {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
}

function nonNegativeNumber(value: string) {
  if (!value.trim()) {
    return null;
  }

  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function invalidHabit(message: string): ParsedHabitResult {
  return { message, success: false };
}

function invalidOccurrence(message: string): ParsedHabitOccurrenceResult {
  return { message, success: false };
}
