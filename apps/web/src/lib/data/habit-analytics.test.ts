import { describe, expect, it } from "vitest";
import {
  calculateHabitYearStats,
  calendarGridPosition,
  type HabitCalendarDay,
} from "./habit-analytics";

function day(
  localDate: string,
  status: HabitCalendarDay["status"],
): HabitCalendarDay {
  return {
    isScheduled: status !== "not_scheduled",
    localDate,
    measuredValue: null,
    note: null,
    occurrenceId: null,
    occurrenceRevision: null,
    status,
  };
}

describe("calculateHabitYearStats", () => {
  it("keeps intentional skips neutral for completion and streaks", () => {
    expect(
      calculateHabitYearStats(
        [
          day("2026-01-01", "completed"),
          day("2026-01-02", "skipped"),
          day("2026-01-03", "completed"),
        ],
        "2026-01-03",
      ),
    ).toEqual({
      completed: 2,
      completionRate: 1,
      currentStreak: 2,
      longestStreak: 2,
      missed: 0,
      skipped: 1,
    });
  });

  it("ends a streak on a miss and ignores pending or future dates", () => {
    expect(
      calculateHabitYearStats(
        [
          day("2026-01-01", "completed"),
          day("2026-01-02", "missed"),
          day("2026-01-03", "completed"),
          day("2026-01-04", "pending"),
          day("2026-01-05", "upcoming"),
        ],
        "2026-01-04",
      ),
    ).toMatchObject({
      completed: 2,
      completionRate: 2 / 3,
      currentStreak: 1,
      longestStreak: 1,
      missed: 1,
    });
  });

  it("leaves completion rate empty before a completion or miss", () => {
    expect(
      calculateHabitYearStats([day("2026-01-01", "pending")], "2026-01-01")
        .completionRate,
    ).toBeNull();
  });
});

describe("calendarGridPosition", () => {
  it("aligns a year to Sunday-first calendar rows", () => {
    expect(calendarGridPosition("2026-01-01", "2026-01-01")).toEqual({
      column: 1,
      row: 5,
    });
    expect(calendarGridPosition("2026-01-04", "2026-01-01")).toEqual({
      column: 2,
      row: 1,
    });
  });

  it("rejects malformed dates and dates before the calendar", () => {
    expect(calendarGridPosition("2025-12-31", "2026-01-01")).toBeNull();
    expect(calendarGridPosition("not-a-date", "2026-01-01")).toBeNull();
    expect(calendarGridPosition("2026-13-01", "2026-01-01")).toBeNull();
    expect(calendarGridPosition("2026-02-30", "2026-01-01")).toBeNull();
  });
});
