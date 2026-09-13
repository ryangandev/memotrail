import { describe, expect, it } from "vitest";
import {
  calculateHabitBreakdown,
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

describe("calculateHabitBreakdown", () => {
  it("groups leap-day statuses by month and recorded Monday-first weekday", () => {
    const summary = calculateHabitBreakdown(
      [
        day("2024-02-26", "completed"),
        day("2024-02-27", "skipped"),
        day("2024-02-28", "missed"),
        day("2024-02-29", "completed"),
        day("2024-03-01", "missed"),
        day("2024-03-02", "missed"),
        day("2024-03-03", "pending"),
      ],
      "2024-03-03",
      2024,
    );
    expect(summary.months).toHaveLength(12);
    expect(summary.weekdays).toHaveLength(7);
    expect(summary.months[1]).toEqual({
      label: "Feb",
      completed: 2,
      missed: 1,
      skipped: 1,
      completionRate: 2 / 3,
    });
    expect(summary.months[2]).toMatchObject({
      completed: 0,
      missed: 2,
      skipped: 0,
      completionRate: 0,
    });
    expect(summary.weekdays[0]).toMatchObject({
      label: "Monday",
      completed: 1,
    });
    expect(summary.weekdays[3]).toMatchObject({
      label: "Thursday",
      completed: 1,
    });
    expect(summary.mostMissedWeekdays).toEqual([
      "Wednesday",
      "Friday",
      "Saturday",
    ]);
    expect(summary.mostMisses).toBe(1);
  });

  it("excludes future, other-year, invalid, pending and unassigned dates", () => {
    const summary = calculateHabitBreakdown(
      [
        day("2023-12-31", "missed"),
        day("2024-01-01", "completed"),
        day("2024-01-02", "completed"),
        day("2024-02-30", "missed"),
        day("invalid", "missed"),
        day("2024-01-01", "not_scheduled"),
        day("2024-01-01", "pending"),
        day("2024-01-01", "upcoming"),
      ],
      "2024-01-01",
      2024,
    );
    expect(summary.months[0]).toMatchObject({
      completed: 1,
      missed: 0,
      skipped: 0,
      completionRate: 1,
    });
    expect(summary.months[1].completionRate).toBeNull();
    expect(summary.mostMissedWeekdays).toEqual([]);
  });

  it("keeps skip-only and empty periods neutral", () => {
    const summary = calculateHabitBreakdown(
      [day("2024-03-03", "skipped")],
      "2024-03-03",
      2024,
    );
    expect(summary.months[2]).toMatchObject({
      skipped: 1,
      completionRate: null,
    });
    expect(summary.weekdays[6]).toMatchObject({
      label: "Sunday",
      skipped: 1,
      completionRate: null,
    });
    expect(summary.mostMisses).toBe(0);
    expect(
      calculateHabitBreakdown([], "2024-03-03", 2024).months.every(
        (row) => row.completionRate === null,
      ),
    ).toBe(true);
  });

  it("does not invent weekly-target deficits or accept an invalid cutoff", () => {
    const days = [
      day("2024-03-01", "not_scheduled"),
      day("2024-03-02", "missed"),
    ];
    expect(
      calculateHabitBreakdown(days, "2024-03-03", 2024).months[2].missed,
    ).toBe(1);
    expect(
      calculateHabitBreakdown(days, "2024-02-30", 2024).months.every(
        (row) => row.missed === 0,
      ),
    ).toBe(true);
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
