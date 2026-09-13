import { describe, expect, it } from "vitest";
import {
  parseHabitInput,
  parseHabitOccurrenceInput,
  parseHabitSchedule,
  type HabitInput,
  type HabitOccurrenceInput,
} from "./habit-input";

const habitId = "11111111-1111-4111-8111-111111111111";

function habit(overrides: Partial<HabitInput> = {}): HabitInput {
  return {
    endsOn: null,
    id: null,
    measurementUnit: "",
    name: "  Morning supplement  ",
    revision: null,
    schedule: { kind: "daily" },
    startsOn: "2026-01-01",
    targetValue: "",
    trackingMode: "check",
    ...overrides,
  };
}

function occurrence(
  overrides: Partial<HabitOccurrenceInput> = {},
): HabitOccurrenceInput {
  return {
    expectedRevision: null,
    habitId,
    localDate: "2026-09-02",
    measuredValue: "",
    note: "  Felt easy today.  ",
    status: "completed",
    trackingMode: "check",
    ...overrides,
  };
}

describe("parseHabitInput", () => {
  it("validates explicit Entry links and retains null versus omitted intent", () => {
    expect(
      parseHabitOccurrenceInput(occurrence({ entryId: "not-an-id" })).success,
    ).toBe(false);
    expect(
      parseHabitOccurrenceInput(occurrence({ entryId: habitId })),
    ).toMatchObject({ success: true, data: { entryId: habitId } });
    expect(
      parseHabitOccurrenceInput(occurrence({ entryId: null })),
    ).toMatchObject({ success: true, data: { entryId: null } });
    const legacy = parseHabitOccurrenceInput(occurrence());
    expect(legacy.success && legacy.data.entryId).toBeUndefined();
  });
  it("normalizes a daily Check Habit", () => {
    expect(parseHabitInput(habit())).toMatchObject({
      data: {
        measurementUnit: null,
        name: "Morning supplement",
        schedule: { kind: "daily" },
        targetValue: null,
      },
      success: true,
    });
  });

  it("accepts and normalizes a measured Habit", () => {
    expect(
      parseHabitInput(
        habit({
          measurementUnit: " pages ",
          name: "Read",
          targetValue: "20",
          trackingMode: "measure",
        }),
      ),
    ).toMatchObject({
      data: { measurementUnit: "pages", targetValue: 20 },
      success: true,
    });
  });

  it("requires a valid measurement definition only in Measure mode", () => {
    expect(
      parseHabitInput(habit({ trackingMode: "measure", targetValue: "10" }))
        .success,
    ).toBe(false);
    expect(
      parseHabitInput(habit({ measurementUnit: "times", targetValue: "1" }))
        .success,
    ).toBe(false);
  });

  it("validates active date bounds", () => {
    expect(parseHabitInput(habit({ startsOn: "2026-02-30" })).success).toBe(
      false,
    );
    expect(parseHabitInput(habit({ endsOn: "2025-12-31" })).success).toBe(
      false,
    );
  });

  it("requires an id and positive revision together", () => {
    expect(parseHabitInput(habit({ revision: 2 })).success).toBe(false);
    expect(parseHabitInput(habit({ id: habitId, revision: 2 })).success).toBe(
      true,
    );
  });
});

describe("parseHabitSchedule", () => {
  it("supports every confirmed schedule kind", () => {
    expect(parseHabitSchedule({ kind: "daily" })).toEqual({ kind: "daily" });
    expect(
      parseHabitSchedule({ kind: "weekdays", weekdays: [5, 1, 3] }),
    ).toEqual({ kind: "weekdays", weekdays: [1, 3, 5] });
    expect(parseHabitSchedule({ kind: "weekly_target", target: 3 })).toEqual({
      kind: "weekly_target",
      target: 3,
    });
    expect(parseHabitSchedule({ every_days: 14, kind: "interval" })).toEqual({
      every_days: 14,
      kind: "interval",
    });
  });

  it("rejects duplicate weekdays and out-of-range frequencies", () => {
    expect(
      parseHabitSchedule({ kind: "weekdays", weekdays: [1, 1] }),
    ).toBeNull();
    expect(parseHabitSchedule({ kind: "weekly_target", target: 8 })).toBeNull();
    expect(
      parseHabitSchedule({ every_days: 366, kind: "interval" }),
    ).toBeNull();
  });
});

describe("parseHabitOccurrenceInput", () => {
  it("normalizes a Check completion note", () => {
    expect(parseHabitOccurrenceInput(occurrence())).toMatchObject({
      data: { measuredValue: null, note: "Felt easy today." },
      success: true,
    });
  });

  it("requires a numeric Measure completion", () => {
    expect(
      parseHabitOccurrenceInput(
        occurrence({ trackingMode: "measure", measuredValue: "12.5" }),
      ),
    ).toMatchObject({ data: { measuredValue: 12.5 }, success: true });
    expect(
      parseHabitOccurrenceInput(occurrence({ trackingMode: "measure" }))
        .success,
    ).toBe(false);
  });

  it("keeps non-completion states measurement-free", () => {
    expect(
      parseHabitOccurrenceInput(
        occurrence({ measuredValue: "3", status: "skipped" }),
      ).success,
    ).toBe(false);
    expect(
      parseHabitOccurrenceInput(
        occurrence({ measuredValue: "", status: "missed" }),
      ).success,
    ).toBe(true);
  });

  it("validates identity, local date, and revision", () => {
    expect(
      parseHabitOccurrenceInput(occurrence({ habitId: "not-a-habit" })).success,
    ).toBe(false);
    expect(
      parseHabitOccurrenceInput(occurrence({ localDate: "09/02/2026" }))
        .success,
    ).toBe(false);
    expect(
      parseHabitOccurrenceInput(occurrence({ expectedRevision: 0 })).success,
    ).toBe(false);
  });
});
