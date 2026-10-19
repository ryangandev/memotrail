import { describe, expect, it } from "vitest";
import {
  chapterDateFacts,
  entryDateAddsToTitle,
  entryDateLabel,
  entryTitle,
  validEntryID,
} from "./entry-detail";

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
  it("names an untitled item by its date, never by its writing", () => {
    expect(entryTitle({ ...undated, title: " 学习记录 " })).toBe("学习记录");
    expect(
      entryTitle({
        ...undated,
        title: null,
        occurred_start: "2026-10-19T03:00:00Z",
        occurred_timezone: "America/Los_Angeles",
        date_precision: "exact",
      }),
    ).toBe("Sunday, October 18, 2026");
    expect(entryTitle({ ...undated, title: "" })).toBe("Undated entry");
  });
  it("shows the Date fact only when it says more than the heading", () => {
    const day = {
      ...undated,
      title: null,
      occurred_start: "2026-10-18T12:00:00Z",
      date_precision: "day",
    };
    expect(entryDateAddsToTitle({ ...day, title: "Rainy walk" })).toBe(true);
    expect(entryDateAddsToTitle(day)).toBe(false);
    expect(entryDateAddsToTitle({ ...day, date_precision: "month" })).toBe(
      false,
    );
    expect(entryDateAddsToTitle({ ...day, date_precision: "year" })).toBe(
      false,
    );
    expect(
      entryDateAddsToTitle({
        ...day,
        date_precision: "range",
        occurred_end: "2026-10-20T12:00:00Z",
      }),
    ).toBe(false);
    expect(
      entryDateAddsToTitle({ ...day, occurred_end: "2026-10-20T12:00:00Z" }),
    ).toBe(true);
    expect(entryDateAddsToTitle({ ...day, date_precision: "exact" })).toBe(
      true,
    );
    expect(
      entryDateAddsToTitle({
        ...day,
        date_precision: "approximate",
        occurred_label: "Summer after college",
      }),
    ).toBe(false);
    expect(entryDateAddsToTitle({ ...undated, title: null })).toBe(false);
  });
  it("gives a Chapter its span and duration", () => {
    const now = new Date("2026-10-18T12:00:00Z");
    expect(
      chapterDateFacts(
        {
          ...undated,
          date_precision: "month",
          occurred_start: "2019-03-01T12:00:00Z",
        },
        now,
      ),
    ).toEqual({ duration: "About 7 years 7 months", span: "Since Mar 2019" });
    expect(
      chapterDateFacts(
        {
          ...undated,
          date_precision: "year",
          occurred_end: "2021-01-01T12:00:00Z",
          occurred_start: "2019-01-01T12:00:00Z",
        },
        now,
      ),
    ).toEqual({ duration: "About 2 years", span: "2019 - 2021" });
  });
  it("shows an undated Chapter's description without a duration", () => {
    const now = new Date("2026-10-18T12:00:00Z");
    expect(
      chapterDateFacts(
        {
          ...undated,
          date_precision: "approximate",
          occurred_label: "College years",
        },
        now,
      ),
    ).toEqual({ duration: null, span: "College years" });
    expect(chapterDateFacts(undated, now)).toEqual({
      duration: null,
      span: "Date unknown",
    });
  });
  it("accepts only Entry identities", () => {
    expect(validEntryID("94000000-0000-4000-8000-000000000001")).toBe(true);
    for (const value of ["bad", "", null, 1])
      expect(validEntryID(value)).toBe(false);
  });
});
