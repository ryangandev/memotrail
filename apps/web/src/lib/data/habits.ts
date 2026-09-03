import "server-only";

import { getAuthenticatedContext, type Viewer } from "./inbox";
import type { HabitCalendarDay } from "./habit-analytics";
import {
  parseHabitSchedule,
  type HabitCalendarStatus,
  type HabitSchedule,
  type HabitTrackingMode,
} from "./habit-input";

export type HabitOccurrence = {
  id: string;
  measuredValue: number | null;
  note: string | null;
  revision: number;
  status: "completed" | "missed" | "skipped";
};

export type Habit = {
  createdAt: string;
  endsOn: string | null;
  id: string;
  measurementUnit: string | null;
  name: string;
  occurrence: HabitOccurrence | null;
  revision: number;
  schedule: HabitSchedule;
  startsOn: string;
  status: HabitCalendarStatus;
  targetValue: number | null;
  trackingMode: HabitTrackingMode;
  updatedAt: string;
};

export type HabitsWorkspace = {
  calendar: HabitCalendarDay[];
  calendarError: string | null;
  habits: Habit[];
  inboxCount: number | undefined;
  loadError: string | null;
  referenceDate: string;
  selectedHabitId: string | null;
  selectedYear: number;
  viewer: Viewer;
};

type HabitWorkspaceRow = {
  created_at: string;
  ends_on: string | null;
  entry_id: string | null;
  habit_id: string;
  habit_revision: number;
  local_status: HabitCalendarStatus;
  measured_value: number | string | null;
  measurement_unit: string | null;
  name: string;
  note: string | null;
  occurrence_id: string | null;
  occurrence_revision: number | null;
  schedule: unknown;
  starts_on: string;
  target_value: number | string | null;
  tracking_mode: HabitTrackingMode;
  updated_at: string;
};

type HabitCalendarRow = {
  entry_id: string | null;
  is_scheduled: boolean;
  local_date: string;
  measured_value: number | string | null;
  note: string | null;
  occurrence_id: string | null;
  occurrence_revision: number | null;
  status: HabitCalendarStatus;
};

export async function getHabitsWorkspace({
  habitId = null,
  localDate,
  year,
}: {
  habitId?: string | null;
  localDate: string;
  year: number;
}): Promise<HabitsWorkspace | null> {
  const context = await getAuthenticatedContext();

  if (!context) {
    return null;
  }

  const [habitResult, inboxResult] = await Promise.all([
    context.client.rpc("habits_workspace", { p_local_date: localDate }),
    context.client
      .from("entries")
      .select("id", { count: "exact", head: true })
      .eq("owner_id", context.userId)
      .eq("inbox_status", "unreviewed")
      .is("deleted_at", null),
  ]);
  const rows = habitResult.error
    ? null
    : parseHabitWorkspaceRows(habitResult.data);
  const habits = rows?.map(habitFromRow) ?? [];
  const selectedHabitId =
    habits.find((habit) => habit.id === habitId)?.id ?? habits[0]?.id ?? null;
  const calendarResult = selectedHabitId
    ? await context.client.rpc("habit_year_calendar", {
        p_as_of_date: localDate,
        p_habit_id: selectedHabitId,
        p_year: year,
      })
    : { data: [] as HabitCalendarRow[], error: null };
  const calendarRows = calendarResult.error
    ? null
    : parseHabitCalendarRows(calendarResult.data);

  return {
    calendar: calendarRows?.map(calendarDayFromRow) ?? [],
    calendarError:
      selectedHabitId && (!calendarRows || calendarResult.error)
        ? "MemoTrail could not load this Habit year. Refresh to try again."
        : null,
    habits,
    inboxCount: inboxResult.error ? undefined : (inboxResult.count ?? 0),
    loadError:
      rows && !habitResult.error
        ? null
        : "MemoTrail could not load your Habits. Refresh to try again.",
    referenceDate: localDate,
    selectedHabitId,
    selectedYear: year,
    viewer: context.viewer,
  };
}

function habitFromRow(row: HabitWorkspaceRow): Habit {
  const measuredValue = nullableNumber(row.measured_value);
  const targetValue = nullableNumber(row.target_value);

  return {
    createdAt: row.created_at,
    endsOn: row.ends_on,
    id: row.habit_id,
    measurementUnit: row.measurement_unit,
    name: row.name,
    occurrence: row.occurrence_id
      ? {
          id: row.occurrence_id,
          measuredValue,
          note: row.note,
          revision: row.occurrence_revision ?? 1,
          status: explicitStatus(row.local_status),
        }
      : null,
    revision: row.habit_revision,
    schedule: parseHabitSchedule(row.schedule) ?? { kind: "daily" },
    startsOn: row.starts_on,
    status: row.local_status,
    targetValue,
    trackingMode: row.tracking_mode,
    updatedAt: row.updated_at,
  };
}

function calendarDayFromRow(row: HabitCalendarRow): HabitCalendarDay {
  return {
    isScheduled: row.is_scheduled,
    localDate: row.local_date,
    measuredValue: nullableNumber(row.measured_value),
    note: row.note,
    occurrenceId: row.occurrence_id,
    occurrenceRevision: row.occurrence_revision,
    status: row.status,
  };
}

function parseHabitWorkspaceRows(value: unknown): HabitWorkspaceRow[] | null {
  return arrayOf(value, isHabitWorkspaceRow);
}

function parseHabitCalendarRows(value: unknown): HabitCalendarRow[] | null {
  return arrayOf(value, isHabitCalendarRow);
}

function isHabitWorkspaceRow(value: unknown): value is HabitWorkspaceRow {
  if (!isRecord(value) || !parseHabitSchedule(value.schedule)) {
    return false;
  }

  return (
    typeof value.habit_id === "string" &&
    typeof value.name === "string" &&
    (value.tracking_mode === "check" || value.tracking_mode === "measure") &&
    nullableString(value.measurement_unit) &&
    nullableNumeric(value.target_value) &&
    typeof value.starts_on === "string" &&
    nullableString(value.ends_on) &&
    typeof value.habit_revision === "number" &&
    nullableString(value.occurrence_id) &&
    nullableNumberValue(value.occurrence_revision) &&
    isCalendarStatus(value.local_status) &&
    nullableNumeric(value.measured_value) &&
    nullableString(value.note) &&
    nullableString(value.entry_id) &&
    typeof value.created_at === "string" &&
    typeof value.updated_at === "string"
  );
}

function isHabitCalendarRow(value: unknown): value is HabitCalendarRow {
  return (
    isRecord(value) &&
    typeof value.local_date === "string" &&
    typeof value.is_scheduled === "boolean" &&
    isCalendarStatus(value.status) &&
    nullableNumeric(value.measured_value) &&
    nullableString(value.note) &&
    nullableString(value.entry_id) &&
    nullableString(value.occurrence_id) &&
    nullableNumberValue(value.occurrence_revision)
  );
}

function explicitStatus(value: HabitCalendarStatus) {
  return value === "completed" || value === "missed" || value === "skipped"
    ? value
    : "completed";
}

function isCalendarStatus(value: unknown): value is HabitCalendarStatus {
  return (
    value === "completed" ||
    value === "missed" ||
    value === "skipped" ||
    value === "not_scheduled" ||
    value === "pending" ||
    value === "upcoming"
  );
}

function arrayOf<T>(
  value: unknown,
  predicate: (item: unknown) => item is T,
): T[] | null {
  return Array.isArray(value) && value.every(predicate) ? value : null;
}

function nullableNumber(value: number | string | null) {
  if (value === null) {
    return null;
  }

  const number = typeof value === "number" ? value : Number(value);
  return Number.isFinite(number) ? number : null;
}

function nullableNumeric(value: unknown) {
  return (
    value === null ||
    (typeof value === "number" && Number.isFinite(value)) ||
    (typeof value === "string" &&
      value.trim() !== "" &&
      Number.isFinite(Number(value)))
  );
}

function nullableNumberValue(value: unknown) {
  return (
    value === null || (typeof value === "number" && Number.isFinite(value))
  );
}

function nullableString(value: unknown) {
  return value === null || typeof value === "string";
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}
