import { describe, expect, it } from "vitest";
import { entryDateLabel, entryTitle, validEntryID } from "./entry-detail";

const undated = {
  occurred_start: null,
  occurred_end: null,
  date_precision: "unknown",
  occurred_label: null,
  occurred_timezone: "UTC",
};

describe("Entry detail", () => {
  it("formats only known date precision in the original timezone", () => {
    expect(
      entryDateLabel({
        ...undated,
        occurred_start: "2021-01-01T01:00:00Z",
        occurred_timezone: "America/New_York",
        date_precision: "year",
      }),
    ).toBe("2020");
    expect(entryDateLabel({ ...undated, occurred_label: "Age 17" })).toBe(
      "Age 17",
    );
    expect(entryDateLabel(undated)).toBe("Unknown");
  });
  it("handles body-only and empty titles", () => {
    expect(entryTitle({ title: null, body: "  学习记录 " })).toBe("学习记录");
    expect(entryTitle({ title: null })).toBe("Untitled item");
  });
  it("accepts only Entry identities", () => {
    expect(validEntryID("94000000-0000-4000-8000-000000000001")).toBe(true);
    for (const value of ["bad", "", null, 1])
      expect(validEntryID(value)).toBe(false);
  });
});
