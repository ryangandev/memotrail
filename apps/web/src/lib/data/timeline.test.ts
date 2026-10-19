import { describe, expect, it, vi } from "vitest";
vi.mock("server-only", () => ({}));
vi.mock("@/lib/data/inbox", () => ({ getAuthenticatedContext: vi.fn() }));
vi.mock("@/lib/data/tag-options", () => ({ loadTagOptions: vi.fn() }));
import { timelineItems, timelineRows, type TimelineRow } from "./timeline";

function row(overrides: Partial<TimelineRow> = {}): TimelineRow {
  return {
    date_precision: "day",
    entry_id: "entry-1",
    is_chapter: false,
    is_first_time: true,
    occurred_end: null,
    occurred_label: null,
    occurred_start: "2021-06-15T12:00:00Z",
    occurred_timezone: "UTC",
    revision: 1,
    tag_names: [],
    title: "First solo hike",
    updated_at: "2026-09-24T00:00:00Z",
    window_end: "2021-06-16",
    window_start: "2021-06-15",
    ...overrides,
  };
}

describe("Timeline rows", () => {
  it("accepts rows the database returns", () => {
    expect(timelineRows([row(), row({ window_end: null })])).toHaveLength(2);
    expect(timelineRows([])).toEqual([]);
  });

  it("rejects anything that is not exactly a Timeline row", () => {
    expect(timelineRows(null)).toBeNull();
    expect(timelineRows([{ ...row(), is_chapter: "yes" }])).toBeNull();
    expect(timelineRows([{ ...row(), window_start: "June 2021" }])).toBeNull();
    expect(timelineRows([{ ...row(), tag_names: [1] }])).toBeNull();
    expect(timelineRows([{ ...row(), title: null }])).toBeNull();
  });

  it("splits Chapters from First Times and keeps a First Time Chapter as one bar", () => {
    const result = timelineItems([
      row({ entry_id: "point", title: "Point" }),
      row({
        entry_id: "bar-first",
        is_chapter: true,
        title: "Bar and first",
        window_start: "2019-01-01",
      }),
      row({
        entry_id: "bar",
        is_chapter: true,
        is_first_time: false,
        title: "Bar",
        window_start: "2020-01-01",
      }),
    ]);

    expect(result.chapters.map((item) => item.id)).toEqual([
      "bar-first",
      "bar",
    ]);
    expect(result.firstTimes.map((item) => item.id)).toEqual(["point"]);
  });

  it("keeps items without a calendar date, last, with null windows", () => {
    const result = timelineItems([
      row({
        entry_id: "unanchored",
        is_chapter: true,
        is_first_time: false,
        date_precision: "unknown",
        occurred_start: null,
        title: "Roughly college",
        window_end: null,
        window_start: null,
      }),
      row({
        entry_id: "dated",
        is_chapter: true,
        is_first_time: false,
        title: "Dated",
      }),
    ]);

    expect(result.chapters.map((item) => item.id)).toEqual([
      "dated",
      "unanchored",
    ]);
    expect(result.chapters[1]).toMatchObject({
      windowEnd: null,
      windowStart: null,
    });
  });

  it("titles an untitled item by its date", () => {
    const [item] = timelineItems([row({ title: "" })]).firstTimes;

    expect(item?.title).not.toBe("");
    expect(item?.untitled).toBe(true);
    expect(timelineItems([row()]).firstTimes[0]?.untitled).toBe(false);
  });
});
