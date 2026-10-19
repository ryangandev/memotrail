import { describe, expect, it } from "vitest";
import type { Occurrence } from "./occurrence";
import {
  chapterRelation,
  chaptersContaining,
  occurrenceWindow,
  windowContains,
} from "./occurrence-window";

const at = (
  datePrecision: Occurrence["datePrecision"],
  occurredAt: string | null,
  occurredEnd: string | null = null,
  occurredTimezone = "UTC",
): Occurrence => ({
  datePrecision,
  occurredAt,
  occurredEnd,
  occurredLabel: null,
  occurredTimezone,
});

describe("Occurrence windows", () => {
  it("covers the days a date names, in the zone it was recorded in", () => {
    expect(occurrenceWindow(at("day", "2026-10-14T12:00:00Z"), false)).toEqual(
      { first: "2026-10-14", last: "2026-10-14" },
    );
    // Late evening in New York is already the next day in UTC.
    expect(
      occurrenceWindow(
        at("exact", "2026-10-15T02:30:00Z", null, "America/New_York"),
        false,
      ),
    ).toEqual({ first: "2026-10-14", last: "2026-10-14" });
    expect(
      occurrenceWindow(at("month", "2024-02-10T12:00:00Z"), false),
    ).toEqual({ first: "2024-02-01", last: "2024-02-29" });
    expect(
      occurrenceWindow(
        at("year", "2017-06-01T12:00:00Z", "2021-01-01T12:00:00Z"),
        true,
      ),
    ).toEqual({ first: "2017-01-01", last: "2021-12-31" });
  });

  it("leaves a Chapter or range without an end open, and an unknown date empty", () => {
    expect(occurrenceWindow(at("day", "2026-01-05T12:00:00Z"), true)).toEqual({
      first: "2026-01-05",
      last: null,
    });
    expect(
      occurrenceWindow(at("range", "2026-01-05T12:00:00Z"), false),
    ).toEqual({ first: "2026-01-05", last: null });
    expect(occurrenceWindow(at("unknown", null), true)).toBeNull();
    expect(occurrenceWindow(at("day", null), false)).toBeNull();
    expect(
      occurrenceWindow(
        at("day", "2026-02-01T12:00:00Z", "2026-01-01T12:00:00Z"),
        true,
      ),
    ).toBeNull();
  });

  it("contains a window only when every day of it is inside", () => {
    const open = { first: "2026-01-01", last: null };
    const closed = { first: "2026-01-01", last: "2026-06-30" };
    expect(windowContains(open, closed)).toBe(true);
    expect(windowContains(closed, open)).toBe(false);
    expect(
      windowContains(closed, { first: "2026-06-30", last: "2026-07-01" }),
    ).toBe(false);
    expect(
      windowContains(closed, { first: "2025-12-31", last: "2026-01-01" }),
    ).toBe(false);
  });

  it("calls a Chapter inside another only when all its days are", () => {
    const search = at("day", "2026-01-05T12:00:00Z");
    expect(
      chapterRelation(
        search,
        at("day", "2026-09-02T12:00:00Z", "2026-10-17T12:00:00Z"),
      ),
    ).toBe("inside");
    expect(chapterRelation(search, at("month", "2024-08-01T12:00:00Z"))).toBe(
      "overlaps",
    );
  });

  it("lists the Chapters that hold an Entry, innermost first", () => {
    const chapters = [
      { id: "city", occurrence: at("month", "2024-08-01T12:00:00Z") },
      { id: "search", occurrence: at("day", "2026-01-05T12:00:00Z") },
      {
        id: "interviews",
        occurrence: at("day", "2026-09-02T12:00:00Z", "2026-10-17T12:00:00Z"),
      },
      {
        id: "earlier",
        occurrence: at("day", "2025-01-01T12:00:00Z", "2025-12-31T12:00:00Z"),
      },
      { id: "undated", occurrence: at("unknown", null) },
    ];
    expect(
      chaptersContaining(at("day", "2026-10-09T12:00:00Z"), chapters).map(
        (chapter) => chapter.id,
      ),
    ).toEqual(["interviews", "search", "city"]);
    // An Entry known only to the year needs a Chapter that holds the whole year.
    expect(
      chaptersContaining(at("year", "2026-03-01T12:00:00Z"), chapters).map(
        (chapter) => chapter.id,
      ),
    ).toEqual(["city"]);
    expect(chaptersContaining(at("unknown", null), chapters)).toEqual([]);
  });
});
