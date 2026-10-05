import { describe, expect, it } from "vitest";
import {
  createTimelineLayout,
  type TimelineLayoutSource,
} from "./timeline-layout";

const reference = new Date("2026-09-02T12:00:00.000Z");

function source(
  overrides: Partial<TimelineLayoutSource> = {},
): TimelineLayoutSource {
  return {
    id: "moment-1",
    labelWidthPixels: 80,
    shape: "moment",
    occurredEnd: null,
    occurredStart: "2020-01-01T12:00:00.000Z",
    lane: "other",
    ...overrides,
  };
}

describe("createTimelineLayout", () => {
  it("never invents calendar positions for unanchored periods or moments", () => {
    const layout = createTimelineLayout(
      [
        source({ occurredStart: null }),
        source({ id: "period", shape: "period", occurredStart: null }),
      ],
      reference,
    );
    expect(layout).toEqual(createTimelineLayout([], reference));
  });
  it("builds a stable current-year range for an empty Timeline", () => {
    const layout = createTimelineLayout([], reference);

    expect(layout.start).toBe("2026-01-01T00:00:00.000Z");
    expect(layout.end).toBe("2027-01-01T00:00:00.000Z");
    expect(layout.positions).toEqual([]);
  });

  it("starts an empty Timeline at the owner's birth date and continues to today", () => {
    const layout = createTimelineLayout([], reference, "1994-04-18");

    expect(layout.start).toBe("1994-04-18T00:00:00.000Z");
    expect(layout.yearMarkers[0]).toEqual({
      label: "1994",
      leftPercent: 0,
      year: 1994,
    });
    expect(new Date(layout.end).getTime()).toBeGreaterThan(reference.getTime());
  });

  it("does not move the Timeline before birth for an earlier imported moment", () => {
    const layout = createTimelineLayout(
      [source({ occurredStart: "1990-01-01T00:00:00.000Z" })],
      reference,
      "1994-04-18",
    );

    expect(layout.start).toBe("1994-04-18T00:00:00.000Z");
    expect(layout.positions[0]?.leftPercent).toBe(0);
  });

  it("orders a moment within padded bounds", () => {
    const layout = createTimelineLayout([source()], reference);
    const position = layout.positions[0];

    expect(position?.leftPercent).toBeGreaterThan(0);
    expect(position?.leftPercent).toBeLessThan(100);
    expect(position?.barWidthPixels).toBe(12);
    expect(position?.labelPlacement).toBe("after");
  });

  it("extends an open period to the reference date", () => {
    const layout = createTimelineLayout(
      [
        source({
          id: "period-1",
          shape: "period",
          occurredStart: "2024-01-01T12:00:00.000Z",
        }),
      ],
      reference,
    );

    expect(layout.positions[0]?.widthPixels).toBeGreaterThan(
      layout.canvasWidth / 2,
    );
    expect(layout.positions[0]?.labelPlacement).toBe("inside");
  });

  it("stacks overlapping periods on different rows", () => {
    const layout = createTimelineLayout(
      [
        source({
          id: "period-1",
          shape: "period",
          occurredEnd: "2024-12-01T12:00:00.000Z",
          occurredStart: "2020-01-01T12:00:00.000Z",
        }),
        source({
          id: "period-2",
          shape: "period",
          occurredEnd: "2025-01-01T12:00:00.000Z",
          occurredStart: "2022-01-01T12:00:00.000Z",
        }),
      ],
      reference,
    );

    expect(layout.positions.map((item) => item.row)).toEqual([0, 1]);
    expect(layout.rowCountByLane.other).toBe(2);
  });

  it("reuses a row for periods that no longer overlap", () => {
    const layout = createTimelineLayout(
      [
        source({
          id: "period-1",
          shape: "period",
          occurredEnd: "2021-01-01T12:00:00.000Z",
        }),
        source({
          id: "period-2",
          shape: "period",
          occurredEnd: "2023-01-01T12:00:00.000Z",
          occurredStart: "2022-01-01T12:00:00.000Z",
        }),
      ],
      reference,
    );

    expect(layout.positions.map((item) => item.row)).toEqual([0, 0]);
    expect(layout.rowCountByLane.other).toBe(1);
  });

  it("reuses a row for short non-overlapping periods on a life-long Timeline", () => {
    const layout = createTimelineLayout(
      [
        source({
          id: "walmart",
          labelWidthPixels: 44,
          shape: "period",
          occurredEnd: "2026-01-31T00:00:00.000Z",
          occurredStart: "2025-05-19T00:00:00.000Z",
          lane: "work_study",
        }),
        source({
          id: "adobe",
          labelWidthPixels: 34,
          shape: "period",
          occurredStart: "2026-04-13T00:00:00.000Z",
          lane: "work_study",
        }),
      ],
      reference,
      "2000-05-16",
    );

    expect(layout.positions.map((item) => item.row)).toEqual([0, 0]);
    expect(layout.rowCountByLane.work_study).toBe(1);
  });

  it("separates moments whose rendered labels overlap", () => {
    const layout = createTimelineLayout(
      [
        source({
          id: "moment-1",
          occurredStart: "2026-01-01T00:00:00.000Z",
        }),
        source({
          id: "moment-2",
          occurredStart: "2026-06-01T00:00:00.000Z",
        }),
      ],
      reference,
      "2000-05-16",
    );

    expect(layout.positions.map((item) => item.row)).toEqual([0, 1]);
    expect(layout.rowCountByLane.other).toBe(2);
  });

  it("aligns short ongoing period bars to their shared present endpoint", () => {
    const layout = createTimelineLayout(
      [
        source({
          id: "adobe",
          labelWidthPixels: 30,
          shape: "period",
          occurredStart: "2026-04-13T00:00:00.000Z",
          lane: "work_study",
        }),
        source({
          id: "evergreen",
          labelWidthPixels: 30,
          shape: "period",
          occurredStart: "2026-09-01T00:00:00.000Z",
          lane: "homes",
        }),
      ],
      reference,
      "2000-05-16",
    );
    const rightEdges = layout.positions.map(
      (position) =>
        (position.leftPercent / 100) * layout.canvasWidth +
        position.offsetPixels +
        position.barWidthPixels,
    );
    const today = (layout.todayPercent / 100) * layout.canvasWidth;

    expect(layout.positions.map((position) => position.labelPlacement)).toEqual(
      ["after", "after"],
    );

    expect(rightEdges[0]).toBeCloseTo(rightEdges[1]!, 5);
    expect(rightEdges[0]).toBeCloseTo(today, 5);
  });

  it("puts a title beside a Period too short to hold it, never cut off", () => {
    const layout = createTimelineLayout(
      [
        source({
          id: "ended",
          labelWidthPixels: 64,
          shape: "period",
          occurredEnd: "2010-06-01T00:00:00.000Z",
          occurredStart: "2010-01-01T00:00:00.000Z",
        }),
        source({
          id: "ongoing",
          labelWidthPixels: 40,
          shape: "period",
          occurredStart: "2026-04-13T00:00:00.000Z",
          lane: "work_study",
        }),
        source({
          id: "wide",
          labelWidthPixels: 64,
          shape: "period",
          occurredEnd: "2020-01-01T00:00:00.000Z",
          occurredStart: "2012-01-01T00:00:00.000Z",
          lane: "homes",
        }),
      ],
      reference,
      "2000-05-16",
    );
    const [ended, ongoing, wide] = ["ended", "ongoing", "wide"].map((id) =>
      layout.positions.find((position) => position.id === id),
    );

    expect(ended?.labelPlacement).toBe("after");
    expect(ended?.offsetPixels).toBe(0);
    expect(ended?.labelWidthPixels).toBe(64);
    expect(ended?.widthPixels).toBeCloseTo(ended!.barWidthPixels + 7 + 64, 5);
    // An ongoing bar still ends at today, with its title after the Today line.
    expect(ongoing?.labelPlacement).toBe("after");
    expect(ongoing?.offsetPixels).toBeLessThanOrEqual(0);
    expect(wide?.labelPlacement).toBe("inside");
    expect(wide?.offsetPixels).toBe(0);
  });

  it("keeps a short Period's bar visible and caps a long title beside it", () => {
    const layout = createTimelineLayout(
      [
        source({
          id: "week",
          labelWidthPixels: 400,
          shape: "period",
          occurredEnd: "2010-01-08T00:00:00.000Z",
          occurredStart: "2010-01-01T00:00:00.000Z",
        }),
      ],
      reference,
      "2000-05-16",
    );

    expect(layout.positions[0]?.barWidthPixels).toBe(10);
    expect(layout.positions[0]?.labelWidthPixels).toBe(180);
  });

  it("puts a Moment's title before its dot only when it would pass the end", () => {
    const layout = createTimelineLayout(
      [
        source({ id: "early", occurredStart: "2010-01-01T00:00:00.000Z" }),
        source({
          id: "late",
          lane: "work_study",
          occurredStart: "2026-08-01T00:00:00.000Z",
        }),
      ],
      reference,
      "2000-05-16",
    );
    const [early, late] = layout.positions;

    expect(early?.labelPlacement).toBe("after");
    expect(early?.offsetPixels).toBe(-6);
    expect(late?.labelPlacement).toBe("before");
    expect(late?.offsetPixels).toBe(-(7 + 80 + 6));
  });

  it("stacks rows independently in each lane", () => {
    const layout = createTimelineLayout(
      [source(), source({ id: "moment-2", lane: "work_study" })],
      reference,
    );

    expect(layout.positions.map((item) => item.row)).toEqual([0, 0]);
  });
});
