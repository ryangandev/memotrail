import { describe, expect, it } from "vitest";
import type { TimelineItem } from "./timeline";
import {
  timelineItemAccessibleName,
  timelineItemDateLabel,
  timelineItemDurationLabel,
  timelineUndatedLabel,
} from "./timeline-presentation";

function item(overrides: Partial<TimelineItem> = {}): TimelineItem {
  return {
    id: "entry-1",
    isChapter: false,
    isFirstTime: true,
    occurrence: {
      datePrecision: "unknown",
      occurredAt: null,
      occurredEnd: null,
      occurredLabel: null,
      occurredTimezone: "UTC",
    },
    revision: 1,
    tagNames: [],
    title: "First solo hike",
    updatedAt: "2026-09-24T00:00:00Z",
    windowEnd: null,
    windowStart: null,
    ...overrides,
  };
}

describe("Timeline date labels", () => {
  it("keeps an approximate description and an unknown date", () => {
    expect(
      timelineItemDateLabel(
        item({
          occurrence: {
            datePrecision: "approximate",
            occurredAt: null,
            occurredEnd: null,
            occurredLabel: "Around my twenties",
            occurredTimezone: "UTC",
          },
        }),
      ),
    ).toBe("Around my twenties");
    expect(timelineItemDateLabel(item())).toBe("Date unknown");
  });

  it("shows a First Time's exact date in its recorded time zone", () => {
    expect(
      timelineItemDateLabel(
        item({
          occurrence: {
            datePrecision: "exact",
            occurredAt: "2025-01-01T01:00:00.000Z",
            occurredEnd: null,
            occurredLabel: null,
            occurredTimezone: "America/Los_Angeles",
          },
        }),
      ),
    ).toContain("Dec 31, 2024");
  });

  it("shows a finished Chapter's span and an ongoing one as since", () => {
    const chapter = (occurredEnd: string | null) =>
      item({
        isChapter: true,
        isFirstTime: false,
        occurrence: {
          datePrecision: "month",
          occurredAt: "2019-03-01T12:00:00Z",
          occurredEnd,
          occurredLabel: null,
          occurredTimezone: "UTC",
        },
        windowStart: "2019-03-01",
      });
    expect(timelineItemDateLabel(chapter("2021-06-01T12:00:00Z"))).toBe(
      "Mar 2019 - Jun 2021",
    );
    expect(timelineItemDateLabel(chapter(null))).toBe("Since Mar 2019");
  });

  it("measures a dated Chapter and never a First Time or an undated one", () => {
    const now = new Date("2026-09-02T12:00:00Z");
    const chapter = item({
      isChapter: true,
      isFirstTime: false,
      occurrence: {
        datePrecision: "year",
        occurredAt: "2019-01-01T12:00:00Z",
        occurredEnd: null,
        occurredLabel: null,
        occurredTimezone: "UTC",
      },
      windowStart: "2019-01-01",
    });
    expect(timelineItemDurationLabel(chapter, now)).toBe("About 7 years");
    expect(timelineItemDurationLabel(item(), now)).toBeNull();
    expect(
      timelineItemDurationLabel({ ...chapter, windowStart: null }, now),
    ).toBeNull();
  });

  it("describes an item without a calendar date", () => {
    expect(timelineUndatedLabel(item())).toBe("Undated");
    expect(
      timelineUndatedLabel(
        item({
          occurrence: {
            datePrecision: "approximate",
            occurredAt: null,
            occurredEnd: null,
            occurredLabel: "college years",
            occurredTimezone: "UTC",
          },
        }),
      ),
    ).toBe("Roughly: college years");
  });

  it("names a bar or point by its title and date", () => {
    expect(timelineItemAccessibleName(item())).toBe(
      "First solo hike, Date unknown",
    );
  });
});
