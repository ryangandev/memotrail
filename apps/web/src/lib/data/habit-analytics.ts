import type { HabitCalendarStatus } from "./habit-input";

export type HabitCalendarDay = {
  entryId?: string | null;
  isScheduled: boolean;
  localDate: string;
  measuredValue: number | null;
  note: string | null;
  occurrenceId: string | null;
  occurrenceRevision: number | null;
  status: HabitCalendarStatus;
};

export type HabitYearStats = {
  completed: number;
  completionRate: number | null;
  currentStreak: number;
  longestStreak: number;
  missed: number;
  skipped: number;
};

export type HabitBreakdownRow = {
  label: string;
  completed: number;
  missed: number;
  skipped: number;
  completionRate: number | null;
};

/** Project canonical calendar statuses, never infer additional scheduled misses. */
export function calculateHabitBreakdown(
  days: HabitCalendarDay[],
  asOfDate: string,
  year: number,
) {
  const row = (label: string): HabitBreakdownRow => ({
    label,
    completed: 0,
    missed: 0,
    skipped: 0,
    completionRate: null,
  });
  const months = [
    "Jan",
    "Feb",
    "Mar",
    "Apr",
    "May",
    "Jun",
    "Jul",
    "Aug",
    "Sep",
    "Oct",
    "Nov",
    "Dec",
  ].map(row);
  const weekdays = [
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday",
    "Sunday",
  ].map(row);
  if (parseLocalDate(asOfDate)) {
    for (const day of days) {
      const date = parseLocalDate(day.localDate);
      if (!date || date.getUTCFullYear() !== year || day.localDate > asOfDate)
        continue;
      if (
        day.status !== "completed" &&
        day.status !== "missed" &&
        day.status !== "skipped"
      )
        continue;
      for (const bucket of [
        months[date.getUTCMonth()],
        weekdays[(date.getUTCDay() + 6) % 7],
      ]) {
        bucket[day.status] += 1;
      }
    }
  }
  for (const bucket of [...months, ...weekdays]) {
    const observed = bucket.completed + bucket.missed;
    bucket.completionRate = observed === 0 ? null : bucket.completed / observed;
  }
  const mostMisses = Math.max(...weekdays.map((day) => day.missed));
  return {
    months,
    weekdays,
    mostMisses,
    mostMissedWeekdays:
      mostMisses === 0
        ? []
        : weekdays
            .filter((day) => day.missed === mostMisses)
            .map((day) => day.label),
  };
}

export function calculateHabitYearStats(
  days: HabitCalendarDay[],
  asOfDate: string,
): HabitYearStats {
  const observed = [...days]
    .filter((day) => day.localDate <= asOfDate)
    .sort((a, b) => a.localDate.localeCompare(b.localDate));
  let completed = 0;
  let currentStreak = 0;
  let longestStreak = 0;
  let missed = 0;
  let skipped = 0;

  for (const day of observed) {
    if (day.status === "completed") {
      completed += 1;
      currentStreak += 1;
      longestStreak = Math.max(longestStreak, currentStreak);
    } else if (day.status === "missed") {
      missed += 1;
      currentStreak = 0;
    } else if (day.status === "skipped") {
      skipped += 1;
    }
  }

  return {
    completed,
    completionRate:
      completed + missed === 0 ? null : completed / (completed + missed),
    currentStreak,
    longestStreak,
    missed,
    skipped,
  };
}

export function calendarGridPosition(localDate: string, firstDate: string) {
  const current = parseLocalDate(localDate);
  const first = parseLocalDate(firstDate);

  if (!current || !first || current < first) {
    return null;
  }

  const dayOffset = Math.round(
    (current.getTime() - first.getTime()) / 86_400_000,
  );
  const row = current.getUTCDay() + 1;
  const column = Math.floor((dayOffset + first.getUTCDay()) / 7) + 1;

  return { column, row };
}

function parseLocalDate(value: string) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    return null;
  }

  const [year, month, day] = value.split("-").map(Number);
  const result = new Date(Date.UTC(year, month - 1, day));

  return result.getUTCFullYear() === year &&
    result.getUTCMonth() === month - 1 &&
    result.getUTCDate() === day
    ? result
    : null;
}
