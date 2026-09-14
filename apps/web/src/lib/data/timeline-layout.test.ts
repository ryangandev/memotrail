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
    id: "event-1",
    kind: "event",
    occurredEnd: null,
    occurredStart: "2020-01-01T12:00:00.000Z",
    trackId: "places",
    ...overrides,
  };
}

describe("createTimelineLayout", () => {
  it("never invents calendar positions for unanchored stages or events", () => {
    const layout = createTimelineLayout(
      [
        source({ occurredStart: null }),
        source({ id: "stage", kind: "stage", occurredStart: null }),
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

  it("orders an event within padded bounds", () => {
    const layout = createTimelineLayout([source()], reference);
    const position = layout.positions[0];

    expect(position?.leftPercent).toBeGreaterThan(0);
    expect(position?.leftPercent).toBeLessThan(100);
    expect(position?.widthPercent).toBe(0);
  });

  it("extends an open stage to the reference date", () => {
    const layout = createTimelineLayout(
      [
        source({
          id: "stage-1",
          kind: "stage",
          occurredStart: "2024-01-01T12:00:00.000Z",
        }),
      ],
      reference,
    );

    expect(layout.positions[0]?.widthPercent).toBeGreaterThan(50);
  });

  it("places overlapping periods in different lanes", () => {
    const layout = createTimelineLayout(
      [
        source({
          id: "stage-1",
          kind: "stage",
          occurredEnd: "2024-12-01T12:00:00.000Z",
          occurredStart: "2020-01-01T12:00:00.000Z",
        }),
        source({
          id: "stage-2",
          kind: "stage",
          occurredEnd: "2025-01-01T12:00:00.000Z",
          occurredStart: "2022-01-01T12:00:00.000Z",
        }),
      ],
      reference,
    );

    expect(layout.positions.map((item) => item.lane)).toEqual([0, 1]);
    expect(layout.laneCountByTrack.places).toBe(2);
  });

  it("reuses a lane for periods that no longer overlap", () => {
    const layout = createTimelineLayout(
      [
        source({
          id: "stage-1",
          kind: "stage",
          occurredEnd: "2021-01-01T12:00:00.000Z",
        }),
        source({
          id: "stage-2",
          kind: "stage",
          occurredEnd: "2023-01-01T12:00:00.000Z",
          occurredStart: "2022-01-01T12:00:00.000Z",
        }),
      ],
      reference,
    );

    expect(layout.positions.map((item) => item.lane)).toEqual([0, 0]);
    expect(layout.laneCountByTrack.places).toBe(1);
  });

  it("calculates lanes independently for each track", () => {
    const layout = createTimelineLayout(
      [source(), source({ id: "event-2", trackId: "education" })],
      reference,
    );

    expect(layout.positions.map((item) => item.lane)).toEqual([0, 0]);
  });
});
