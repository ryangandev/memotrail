import { describe, expect, it } from "vitest";
import type { TimelineEntry, TimelineTrack } from "@/lib/data/timeline";
import { createTimelineIdeaModel } from "./model";

function entry(overrides: Partial<TimelineEntry>): TimelineEntry {
  return {
    body: "",
    collectionNames: [],
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

describe("timeline idea model", () => {
  it("keeps unanchored approximate and unknown dates out of calendar groups", () => {
    const track: TimelineTrack = {
      id: "track-1",
      isHidden: false,
      name: "Life",
      sortOrder: 0,
      systemKey: null,
      items: [
        entry({
          id: "approximate",
          datePrecision: "approximate",
          occurredLabel: "Around my twenties",
        }),
        entry({ id: "unknown" }),
      ],
    };

    const model = createTimelineIdeaModel([track]);
    expect(model.dated).toHaveLength(0);
    expect(model.undated.map((item) => item.dateLabel)).toEqual([
      "Around my twenties",
      "Date unknown",
    ]);
  });

  it("groups an anchored exact date in its recorded timezone", () => {
    const track: TimelineTrack = {
      id: "track-1",
      isHidden: false,
      name: "Life",
      sortOrder: 0,
      systemKey: null,
      items: [
        entry({
          datePrecision: "exact",
          occurredStart: "2025-01-01T01:00:00.000Z",
          occurredTimezone: "America/Los_Angeles",
        }),
      ],
    };

    const model = createTimelineIdeaModel([track]);
    expect(model.dated[0]?.year).toBe(2024);
    expect(model.dated[0]?.dateLabel).toContain("Dec 31, 2024");
  });
});
