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
    expect(position?.widthPercent).toBe(0);
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

    expect(layout.positions[0]?.widthPercent).toBeGreaterThan(50);
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
          shape: "period",
          occurredEnd: "2026-01-31T00:00:00.000Z",
          occurredStart: "2025-05-19T00:00:00.000Z",
          lane: "work_study",
        }),
        source({
          id: "adobe",
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

  it("aligns short ongoing period labels to their shared present endpoint", () => {
    const layout = createTimelineLayout(
      [
        source({
          id: "adobe",
          shape: "period",
          occurredStart: "2026-04-13T00:00:00.000Z",
          lane: "work_study",
        }),
        source({
          id: "evergreen",
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
        position.periodLabelOffsetPixels +
        Math.max(position.widthPixels, 54),
    );
    const today = (layout.todayPercent / 100) * layout.canvasWidth;

    expect(rightEdges[0]).toBeCloseTo(rightEdges[1]!, 5);
    expect(rightEdges[0]).toBeCloseTo(today, 5);
  });

  it("stacks rows independently in each lane", () => {
    const layout = createTimelineLayout(
      [source(), source({ id: "moment-2", lane: "work_study" })],
      reference,
    );

    expect(layout.positions.map((item) => item.row)).toEqual([0, 0]);
  });
});
