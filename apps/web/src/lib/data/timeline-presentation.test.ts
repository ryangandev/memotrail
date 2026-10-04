import { describe, expect, it } from "vitest";
import type { TimelineEntry, TimelineTrack } from "./timeline";
import {
  createTimelineDisplayModel,
  groupTimelineYears,
  timelineEntryTypeLabel,
} from "./timeline-presentation";

function entry(overrides: Partial<TimelineEntry>): TimelineEntry {
  return {
    body: "",
    datePrecision: "unknown",
    id: "entry-1",
    itemKind: "entry",
    itemSubtype: "moment",
    kind: "event",
    occurredEnd: null,
    occurredLabel: null,
    occurredStart: null,
    occurredTimezone: "UTC",
    revision: 1,
    tagNames: [],
    title: "Moment",
    trackId: "track-1",
    updatedAt: "2026-09-24T00:00:00Z",
    ...overrides,
  };
}

function track(items: TimelineEntry[]): TimelineTrack {
  return {
    id: "track-1",
    isHidden: false,
    items,
    name: "Life",
    sortOrder: 0,
    systemKey: null,
  };
}

describe("Timeline presentation", () => {
  it("keeps unanchored approximate and unknown dates outside year groups", () => {
    const model = createTimelineDisplayModel([
      track([
        entry({
          id: "approximate",
          datePrecision: "approximate",
          occurredLabel: "Around my twenties",
        }),
        entry({ id: "unknown" }),
      ]),
    ]);
    expect(groupTimelineYears(model)).toEqual([]);
    expect(model.undated.map((item) => item.dateLabel)).toEqual([
      "Around my twenties",
      "Date unknown",
    ]);
  });

  it("groups an exact date in the recorded timezone", () => {
    const model = createTimelineDisplayModel([
      track([
        entry({
          datePrecision: "exact",
          occurredStart: "2025-01-01T01:00:00.000Z",
          occurredTimezone: "America/Los_Angeles",
        }),
      ]),
    ]);
    expect(groupTimelineYears(model)[0]?.[0]).toBe(2024);
    expect(model.dated[0]?.dateLabel).toContain("Dec 31, 2024");
  });

  it("retains focused record identity and the full period date range", () => {
    const model = createTimelineDisplayModel([
      track([
        entry({
          datePrecision: "range",
          itemKind: "entity",
          itemSubtype: "home",
          kind: "stage",
          occurredStart: "2008-09-01T12:00:00Z",
          occurredEnd: "2012-06-01T12:00:00Z",
        }),
      ]),
    ]);
    expect(model.dated[0]?.dateLabel).toContain("2012");
    expect(timelineEntryTypeLabel(model.dated[0].entry)).toBe("Home");
  });
});
