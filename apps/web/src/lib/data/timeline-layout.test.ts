import { describe, expect, it } from "vitest";
import {
  createTimelineLayout,
  type TimelineLayoutSource,
} from "./timeline-layout";

const reference = new Date("2026-09-02T12:00:00.000Z");

function point(
  overrides: Partial<TimelineLayoutSource> = {},
): TimelineLayoutSource {
  return {
    band: "first-times",
    id: "point-1",
    labelWidthPixels: 80,
    shape: "point",
    windowEnd: null,
    windowStart: "2020-01-01",
    ...overrides,
  };
}

function bar(
  overrides: Partial<TimelineLayoutSource> = {},
): TimelineLayoutSource {
  return point({
    band: "chapters",
    id: "bar-1",
    shape: "bar",
    ...overrides,
  });
}

describe("createTimelineLayout", () => {
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

  it("does not move the Timeline before birth for an earlier imported First Time", () => {
    const layout = createTimelineLayout(
      [point({ windowStart: "1990-01-01" })],
      reference,
      "1994-04-18",
    );

    expect(layout.start).toBe("1994-04-18T00:00:00.000Z");
    expect(layout.positions[0]?.leftPercent).toBe(0);
  });

  it("places a point within padded bounds", () => {
    const layout = createTimelineLayout([point()], reference);
    const position = layout.positions[0];

    expect(position?.leftPercent).toBeGreaterThan(0);
    expect(position?.leftPercent).toBeLessThan(100);
    expect(position?.barWidthPixels).toBe(12);
    expect(position?.labelPlacement).toBe("after");
  });

  it("draws a bar from its window start to its window end", () => {
    const layout = createTimelineLayout(
      [bar({ windowEnd: "2022-01-01", windowStart: "2020-01-01" })],
      reference,
      "2000-01-01",
    );
    const position = layout.positions[0]!;
    const marker = (year: number) =>
      layout.yearMarkers.find((item) => item.year === year)!.leftPercent;

    expect(position.leftPercent).toBeCloseTo(marker(2020), 5);
    expect(
      position.leftPercent +
        (position.barWidthPixels / layout.canvasWidth) * 100,
    ).toBeCloseTo(marker(2022), 5);
  });

  it("lets a Year Chapter reach the next January marker", () => {
    // 2019 to 2021 is stored as the window 2019-01-01 up to, not including, 2022-01-01.
    const layout = createTimelineLayout(
      [bar({ windowEnd: "2022-01-01", windowStart: "2019-01-01" })],
      reference,
      "2000-01-01",
    );
    const position = layout.positions[0]!;
    const end2022 = layout.yearMarkers.find(
      (marker) => marker.year === 2022,
    )!.leftPercent;

    expect(position.labelPlacement).toBe("inside");
    expect(
      position.leftPercent + (position.widthPixels / layout.canvasWidth) * 100,
    ).toBeCloseTo(end2022, 5);
  });

  it("extends an open bar to the reference date", () => {
    const layout = createTimelineLayout(
      [bar({ windowStart: "2024-01-01" })],
      reference,
    );

    expect(layout.positions[0]?.widthPixels).toBeGreaterThan(
      layout.canvasWidth / 2,
    );
    expect(layout.positions[0]?.labelPlacement).toBe("inside");
  });

  it("stacks overlapping bars on different rows", () => {
    const layout = createTimelineLayout(
      [
        bar({
          id: "bar-1",
          windowEnd: "2024-12-01",
          windowStart: "2020-01-01",
        }),
        bar({
          id: "bar-2",
          windowEnd: "2025-01-01",
          windowStart: "2022-01-01",
        }),
      ],
      reference,
    );

    expect(layout.positions.map((item) => item.row)).toEqual([0, 1]);
    expect(layout.rowCountByBand.chapters).toBe(2);
  });

  it("reuses a row for bars that no longer overlap", () => {
    const layout = createTimelineLayout(
      [
        bar({ id: "bar-1", windowEnd: "2021-01-01" }),
        bar({
          id: "bar-2",
          windowEnd: "2023-01-01",
          windowStart: "2022-01-01",
        }),
      ],
      reference,
    );

    expect(layout.positions.map((item) => item.row)).toEqual([0, 0]);
    expect(layout.rowCountByBand.chapters).toBe(1);
  });

  it("reuses a row for short non-overlapping bars on a life-long Timeline", () => {
    const layout = createTimelineLayout(
      [
        bar({
          id: "walmart",
          labelWidthPixels: 44,
          windowEnd: "2026-02-01",
          windowStart: "2025-05-19",
        }),
        bar({
          id: "adobe",
          labelWidthPixels: 34,
          windowStart: "2026-04-13",
        }),
      ],
      reference,
      "2000-05-16",
    );

    expect(layout.positions.map((item) => item.row)).toEqual([0, 0]);
    expect(layout.rowCountByBand.chapters).toBe(1);
  });

  it("separates points whose rendered labels overlap", () => {
    const layout = createTimelineLayout(
      [
        point({ id: "point-1", windowStart: "2026-01-01" }),
        point({ id: "point-2", windowStart: "2026-06-01" }),
      ],
      reference,
      "2000-05-16",
    );

    expect(layout.positions.map((item) => item.row)).toEqual([0, 1]);
    expect(layout.rowCountByBand["first-times"]).toBe(2);
  });

  it("aligns short ongoing bars to their shared present endpoint", () => {
    const layout = createTimelineLayout(
      [
        bar({
          id: "adobe",
          labelWidthPixels: 30,
          windowStart: "2026-04-13",
        }),
        bar({
          id: "evergreen",
          labelWidthPixels: 30,
          windowStart: "2026-09-01",
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

  it("puts a title beside a bar too short to hold it, never cut off", () => {
    const layout = createTimelineLayout(
      [
        bar({
          id: "ended",
          labelWidthPixels: 64,
          windowEnd: "2010-06-02",
          windowStart: "2010-01-01",
        }),
        bar({
          id: "ongoing",
          labelWidthPixels: 40,
          windowStart: "2026-04-13",
        }),
        bar({
          id: "wide",
          labelWidthPixels: 64,
          windowEnd: "2020-01-01",
          windowStart: "2012-01-01",
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

  it("keeps a short bar visible and caps a long title beside it", () => {
    const layout = createTimelineLayout(
      [
        bar({
          id: "week",
          labelWidthPixels: 400,
          windowEnd: "2010-01-09",
          windowStart: "2010-01-01",
        }),
      ],
      reference,
      "2000-05-16",
    );

    expect(layout.positions[0]?.barWidthPixels).toBe(10);
    expect(layout.positions[0]?.labelWidthPixels).toBe(180);
  });

  it("puts a point's title before its dot only when it would pass the end", () => {
    const layout = createTimelineLayout(
      [
        point({ id: "early", windowStart: "2010-01-01" }),
        point({ id: "late", windowStart: "2026-08-01" }),
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

  it("stacks rows independently in each band", () => {
    const layout = createTimelineLayout(
      [point(), bar({ id: "bar-2", windowStart: "2020-01-01" })],
      reference,
    );

    expect(layout.positions.map((item) => item.row)).toEqual([0, 0]);
  });

  it("ignores a window start that is not a calendar date", () => {
    const layout = createTimelineLayout(
      [point({ windowStart: "not a date" })],
      reference,
    );

    expect(layout).toEqual(createTimelineLayout([], reference));
  });

  it("fills the visible width and still widens a long Timeline past it", () => {
    expect(createTimelineLayout([], reference).canvasWidth).toBe(840);
    expect(createTimelineLayout([], reference, null, 1100.6).canvasWidth).toBe(
      1100,
    );
    const long = createTimelineLayout([], reference, "1990-01-01", 1100);
    expect(long.canvasWidth).toBe(long.yearMarkers.length * 112);
    expect(long.canvasWidth).toBeGreaterThan(1100);
    expect(long.monthMarkers).toEqual([]);
  });
});

describe("createTimelineLayout zoomed to months", () => {
  it("gives every month 60 px and marks each month start but January", () => {
    const layout = createTimelineLayout(
      [point({ windowStart: "2025-03-10" })],
      reference,
      null,
      1100,
      "months",
    );
    const months =
      (new Date(layout.end).getTime() - new Date(layout.start).getTime()) /
      ((365.2425 / 12) * 24 * 60 * 60 * 1_000);

    expect(layout.canvasWidth).toBe(Math.ceil(months * 60));
    expect(layout.monthMarkers.some((marker) => marker.month === 1)).toBe(
      false,
    );
    expect(layout.yearMarkers.map((marker) => marker.label)).toEqual([
      "2026",
      "2027",
    ]);
    const april = layout.monthMarkers.find(
      (marker) => marker.year === 2025 && marker.month === 4,
    )!;
    const may = layout.monthMarkers.find(
      (marker) => marker.year === 2025 && marker.month === 5,
    )!;
    expect(april.label).toBe("Apr");
    // April has 30 days, so it is a little narrower than the average month. The canvas rounds
    // up to whole pixels.
    expect(
      ((may.leftPercent - april.leftPercent) / 100) * layout.canvasWidth,
    ).toBeCloseTo((30 / (365.2425 / 12)) * 60, 1);
  });

  it("runs half a year past today so today can sit in the right third", () => {
    const layout = createTimelineLayout(
      [point({ windowStart: "2025-03-10" })],
      reference,
      null,
      1100,
      "months",
    );
    const pastToday = ((100 - layout.todayPercent) / 100) * layout.canvasWidth;

    expect(pastToday).toBeGreaterThanOrEqual(6 * 60 - 1);
    expect(
      createTimelineLayout(
        [point({ windowStart: "2025-03-10" })],
        reference,
        null,
        1100,
      ).end,
    ).not.toBe(layout.end);
  });

  it("places items and stacks rows as it does zoomed to years", () => {
    const items = [
      bar({ id: "bar-1", windowEnd: "2024-12-01", windowStart: "2020-01-01" }),
      bar({ id: "bar-2", windowEnd: "2023-01-01", windowStart: "2022-01-01" }),
      point({ id: "point-1", windowStart: "2021-06-01" }),
    ];
    const months = createTimelineLayout(
      items,
      reference,
      "2000-01-01",
      1100,
      "months",
    );
    const rows = (layout: ReturnType<typeof createTimelineLayout>) =>
      Object.fromEntries(
        layout.positions.map((position) => [position.id, position.row]),
      );

    expect(rows(months)).toEqual({ "bar-1": 0, "bar-2": 1, "point-1": 0 });
    expect(
      months.positions.find((position) => position.id === "bar-2")!
        .barWidthPixels,
    ).toBeCloseTo((365 / (365.2425 / 12)) * 60, 0);
  });

  it("keeps a month start clear of the birth date's year marker", () => {
    const layout = createTimelineLayout(
      [],
      reference,
      "1994-04-18",
      1100,
      "months",
    );

    expect(layout.yearMarkers[0]).toEqual({
      label: "1994",
      leftPercent: 0,
      year: 1994,
    });
    // May 1 is 13 days, about 26 px, after the birth date, so the first month shown is June.
    expect(layout.monthMarkers[0]).toMatchObject({
      label: "Jun",
      month: 6,
      year: 1994,
    });
  });
});
