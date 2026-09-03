import { describe, expect, it } from "vitest";
import { habitsHref, parseHabitsRequest } from "./habits-request";

describe("parseHabitsRequest", () => {
  it("uses the valid requested date, year, and Habit", () => {
    expect(
      parseHabitsRequest(
        {
          date: "2025-12-31",
          habit: "11111111-1111-4111-8111-111111111111",
          year: "2025",
        },
        "2026-09-02",
      ),
    ).toEqual({
      habitId: "11111111-1111-4111-8111-111111111111",
      hasExplicitDate: true,
      referenceDate: "2025-12-31",
      selectedYear: 2025,
    });
  });

  it("falls back from malformed and repeated parameters", () => {
    expect(
      parseHabitsRequest(
        { date: ["not-a-date", "2025-01-01"], year: "3000" },
        "2026-09-02",
      ),
    ).toMatchObject({
      hasExplicitDate: false,
      referenceDate: "2026-09-02",
      selectedYear: 2026,
    });
  });
});

describe("habitsHref", () => {
  it("keeps Habit, date, and year selection durable", () => {
    expect(
      habitsHref({
        date: "2026-09-02",
        habitId: "11111111-1111-4111-8111-111111111111",
        year: 2025,
      }),
    ).toBe(
      "/habits?date=2026-09-02&habit=11111111-1111-4111-8111-111111111111&year=2025",
    );
  });
});
