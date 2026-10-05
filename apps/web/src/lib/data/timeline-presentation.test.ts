import { describe, expect, it } from "vitest";
import type { TimelineEntry } from "./timeline";
import { timelineEntryDateLabel } from "./timeline-presentation";

function entry(overrides: Partial<TimelineEntry>): TimelineEntry {
  return {
    body: "",
    datePrecision: "unknown",
    id: "entry-1",
    itemKind: "entry",
    isFirstTime: false,
    itemSubtype: "entry",
    lane: "other",
    occurredEnd: null,
    occurredLabel: null,
    occurredStart: null,
    occurredTimezone: "UTC",
    revision: 1,
    shape: "moment",
    tagNames: [],
    title: "Moment",
    updatedAt: "2026-09-24T00:00:00Z",
    ...overrides,
  };
}

describe("Timeline date labels", () => {
  it("keeps an approximate description and an unknown date", () => {
    expect(
      timelineEntryDateLabel(
        entry({
          datePrecision: "approximate",
          occurredLabel: "Around my twenties",
        }),
      ),
    ).toBe("Around my twenties");
    expect(timelineEntryDateLabel(entry({}))).toBe("Date unknown");
  });

  it("shows an exact date in its recorded timezone", () => {
    expect(
      timelineEntryDateLabel(
        entry({
          datePrecision: "exact",
          occurredStart: "2025-01-01T01:00:00.000Z",
          occurredTimezone: "America/Los_Angeles",
        }),
      ),
    ).toContain("Dec 31, 2024");
  });

  it("shows a finished Period's full range and an ongoing one as onward", () => {
    expect(
      timelineEntryDateLabel(
        entry({
          datePrecision: "range",
          occurredEnd: "2012-06-01T12:00:00Z",
          occurredStart: "2008-09-01T12:00:00Z",
          shape: "period",
        }),
      ),
    ).toContain("2012");
    expect(
      timelineEntryDateLabel(
        entry({
          datePrecision: "month",
          occurredStart: "2024-03-01T12:00:00Z",
          shape: "period",
        }),
      ),
    ).toMatch(/ onward$/);
  });
});
