import { describe, expect, it } from "vitest";
import type { FirstTimeEntry } from "./first-times";
import type { TimelineTrack } from "./timeline";
import { includeUnplacedFirstTimes } from "./timeline-first-times";

const firstTime: FirstTimeEntry = {
  attachments: [],
  body: "A beginning",
  datePrecision: "day",
  id: "first-1",
  inboxStatus: "organized",
  occurredEnd: null,
  occurredLabel: null,
  occurredStart: "2020-05-01T12:00:00Z",
  occurredTimezone: "America/Los_Angeles",
  revision: 1,
  tagNames: [],
  title: "First trip",
  updatedAt: "2020-05-02T12:00:00Z",
};

const systemTrack: TimelineTrack = {
  id: "first-track",
  isHidden: false,
  items: [],
  name: "First Times",
  sortOrder: 2,
  systemKey: "first_times",
};

describe("First Times Timeline projection", () => {
  it("shows dated First Times without a saved Timeline placement", () => {
    const [track] = includeUnplacedFirstTimes([systemTrack], [firstTime]);
    expect(track.items).toMatchObject([
      {
        id: "first-1",
        itemKind: "entry",
        itemSubtype: "first_time",
        kind: "event",
        trackId: "first-track",
      },
    ]);
  });

  it("does not invent dates or duplicate an existing placement", () => {
    const undated = { ...firstTime, id: "undated", occurredStart: null };
    const otherTrack: TimelineTrack = {
      ...systemTrack,
      id: "other-track",
      systemKey: null,
      items: includeUnplacedFirstTimes([systemTrack], [firstTime])[0].items,
    };
    const tracks = includeUnplacedFirstTimes(
      [systemTrack, otherTrack],
      [firstTime, undated],
    );
    expect(tracks[0].items).toHaveLength(0);
    expect(tracks[1].items).toHaveLength(1);
  });

  it("respects a hidden system track excluded from the visible workspace", () => {
    expect(includeUnplacedFirstTimes([], [firstTime])).toEqual([]);
  });
});
