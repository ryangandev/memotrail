import { describe, expect, it } from "vitest";
import type { TimelineItem } from "./timeline";
import {
  timelineItemAccessibleName,
  timelineItemDateLabel,
  timelineItemDurationLabel,
  timelineChapterSpanLabel,
  timelineRowDateLabel,
  timelineToday,
  timelineUndatedLabel,
  timelineYearGroups,
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
    untitled: false,
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

function dayFirstTime(id: string, day: string, title = id) {
  return item({
    id,
    occurrence: {
      datePrecision: "day",
      occurredAt: `${day}T12:00:00Z`,
      occurredEnd: null,
      occurredLabel: null,
      occurredTimezone: "UTC",
    },
    title,
    windowEnd: null,
    windowStart: day,
  });
}

describe("the vertical Timeline", () => {
  it("groups dated items by year, newest first, with Today in this year", () => {
    const groups = timelineYearGroups(
      [
        dayFirstTime("old", "2024-03-01"),
        dayFirstTime("future", "2026-12-24"),
        dayFirstTime("spring", "2026-04-02"),
        dayFirstTime("fall", "2026-10-14"),
        item({ id: "undated" }),
      ],
      "2026-10-19",
    );

    expect(
      groups.map((group) => [
        group.year,
        group.items.map((member) => member.id),
        group.todayIndex,
      ]),
    ).toEqual([
      [2026, ["future", "fall", "spring"], 1],
      [2024, ["old"], null],
    ]);
  });

  it("keeps this year for the Today rule when nothing started in it", () => {
    expect(
      timelineYearGroups([dayFirstTime("old", "2024-03-01")], "2026-10-19").map(
        (group) => [group.year, group.items.length, group.todayIndex],
      ),
    ).toEqual([
      [2026, 0, 0],
      [2024, 1, null],
    ]);
    expect(timelineYearGroups([], "2026-10-19")).toEqual([
      { items: [], todayIndex: 0, year: 2026 },
    ]);
  });

  it("drops the group's year from a First Time's date", () => {
    expect(timelineRowDateLabel(dayFirstTime("a", "2026-10-14"), 2026)).toBe(
      "Oct 14",
    );
    expect(
      timelineRowDateLabel(
        item({
          occurrence: {
            datePrecision: "range",
            occurredAt: "2025-12-30T12:00:00Z",
            occurredEnd: "2026-01-02T12:00:00Z",
            occurredLabel: null,
            occurredTimezone: "UTC",
          },
          windowStart: "2025-12-30",
        }),
        2025,
      ),
    ).toBe("Dec 30 to Jan 2, 2026");
    expect(
      timelineRowDateLabel(
        item({
          occurrence: {
            datePrecision: "year",
            occurredAt: "2025-01-01T12:00:00Z",
            occurredEnd: null,
            occurredLabel: null,
            occurredTimezone: "UTC",
          },
          windowStart: "2025-01-01",
        }),
        2025,
      ),
    ).toBe("2025");
  });

  it("gives an untitled First Time no date line, since its title is the date", () => {
    expect(
      timelineRowDateLabel(
        { ...dayFirstTime("a", "2024-10-01", "Tuesday, October 1, 2024"), untitled: true },
        2024,
      ),
    ).toBeNull();
  });

  it("reads a Chapter as its span to an end or to now", () => {
    const chapter = (occurredEnd: string | null) =>
      item({
        isChapter: true,
        isFirstTime: false,
        occurrence: {
          datePrecision: "month",
          occurredAt: "2026-09-01T12:00:00Z",
          occurredEnd,
          occurredLabel: null,
          occurredTimezone: "UTC",
        },
        windowStart: "2026-09-01",
      });

    expect(timelineRowDateLabel(chapter("2026-10-01T12:00:00Z"), 2026)).toBe(
      "Sep 2026 to Oct 2026 · Chapter",
    );
    expect(timelineChapterSpanLabel(chapter(null))).toBe("Sep 2026 to now");
  });

  it("finds today's date in the owner's time zone", () => {
    const reference = new Date("2026-10-19T02:00:00Z");

    expect(timelineToday(reference, "UTC")).toBe("2026-10-19");
    expect(timelineToday(reference, "America/Los_Angeles")).toBe("2026-10-18");
    expect(timelineToday(reference, "Not/A_Zone")).toBe("2026-10-19");
  });
});
