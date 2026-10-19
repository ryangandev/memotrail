import { describe, expect, it } from "vitest";
import {
  entryRowDate,
  entryRowDateTime,
  entryRowGroup,
  entryRowLabels,
  entryRowSnippet,
  groupEntryRows,
} from "./entry-row";
import type { Occurrence } from "./occurrence";

const now = new Date("2026-10-19T15:00:00Z");

function occurrence(value: Partial<Occurrence>): Occurrence {
  return {
    datePrecision: "day",
    occurredAt: null,
    occurredEnd: null,
    occurredLabel: null,
    occurredTimezone: "UTC",
    ...value,
  };
}

describe("entryRowDate", () => {
  it("names a day without its year under a month heading", () => {
    const value = occurrence({ occurredAt: "2024-10-17T12:00:00Z" });
    expect(entryRowDate(value, { now, year: "hide" })).toBe("Oct 17");
    expect(entryRowDate(value, { now, year: "show" })).toBe("Oct 17, 2024");
  });

  it("hides the current year automatically", () => {
    expect(
      entryRowDate(occurrence({ occurredAt: "2026-10-17T12:00:00Z" }), { now }),
    ).toBe("Oct 17");
    expect(
      entryRowDate(occurrence({ occurredAt: "2025-10-17T12:00:00Z" }), { now }),
    ).toBe("Oct 17, 2025");
  });

  it("reads an exact time in the zone it was recorded in", () => {
    const value = occurrence({
      datePrecision: "exact",
      occurredAt: "2017-07-10T00:15:00Z",
      occurredTimezone: "America/Los_Angeles",
    });
    expect(entryRowDate(value, { now, year: "show" })).toBe("Jul 9, 2017");
  });

  it("keeps a month or a year at the precision it was recorded", () => {
    expect(
      entryRowDate(
        occurrence({
          datePrecision: "month",
          occurredAt: "2024-10-01T12:00:00Z",
        }),
        { now, year: "hide" },
      ),
    ).toBe("Oct 2024");
    expect(
      entryRowDate(
        occurrence({
          datePrecision: "year",
          occurredAt: "2019-01-01T12:00:00Z",
        }),
        { now },
      ),
    ).toBe("2019");
  });

  it("shows a Chapter's span, naming a shared year once", () => {
    const chapter = (occurredAt: string, occurredEnd: string | null) =>
      entryRowDate(
        occurrence({ datePrecision: "day", occurredAt, occurredEnd }),
        {
          isChapter: true,
          now,
        },
      );
    expect(chapter("2026-01-05T12:00:00Z", null)).toBe("Jan 2026 - now");
    expect(chapter("2025-03-01T12:00:00Z", "2025-06-30T12:00:00Z")).toBe(
      "Mar - Jun 2025",
    );
    expect(chapter("2024-11-01T12:00:00Z", "2025-02-01T12:00:00Z")).toBe(
      "Nov 2024 - Feb 2025",
    );
    expect(chapter("2025-03-01T12:00:00Z", "2025-03-20T12:00:00Z")).toBe(
      "Mar 2025",
    );
  });

  it("shows a remembered period as it was written", () => {
    expect(
      entryRowDate(
        occurrence({
          datePrecision: "approximate",
          occurredAt: "2025-09-01T12:00:00Z",
          occurredLabel: "Fall 2025",
        }),
        { now },
      ),
    ).toBe("Fall 2025");
  });

  it("calls an Entry without a date Undated", () => {
    expect(
      entryRowDate(occurrence({ datePrecision: "unknown" }), { now }),
    ).toBe("Undated");
  });

  it("shortens a range that stays inside a month or a year", () => {
    const range = (start: string, end: string | null) =>
      occurrence({
        datePrecision: "range",
        occurredAt: start,
        occurredEnd: end,
      });
    expect(
      entryRowDate(range("2026-10-17T12:00:00Z", "2026-10-20T12:00:00Z"), {
        now,
      }),
    ).toBe("Oct 17 - 20");
    expect(
      entryRowDate(range("2026-09-28T12:00:00Z", "2026-10-03T12:00:00Z"), {
        now,
        year: "show",
      }),
    ).toBe("Sep 28 - Oct 3, 2026");
    expect(
      entryRowDate(range("2016-01-01T12:00:00Z", "2019-02-03T12:00:00Z"), {
        now,
        year: "hide",
      }),
    ).toBe("Jan 1, 2016 - Feb 3, 2019");
    expect(entryRowDate(range("2026-10-17T12:00:00Z", null), { now })).toBe(
      "Oct 17 onward",
    );
  });

  it("gives a Chapter the months it covers", () => {
    const chapter = (value: Partial<Occurrence>) =>
      entryRowDate(occurrence(value), { isChapter: true, now });
    expect(chapter({ occurredAt: "2026-01-05T12:00:00Z" })).toBe(
      "Jan 2026 - now",
    );
    expect(
      chapter({
        occurredAt: "2023-08-25T12:00:00Z",
        occurredEnd: "2024-03-02T12:00:00Z",
      }),
    ).toBe("Aug 2023 - Mar 2024");
    expect(
      chapter({
        datePrecision: "year",
        occurredAt: "2015-01-01T12:00:00Z",
        occurredEnd: "2020-01-01T12:00:00Z",
      }),
    ).toBe("2015 - 2020");
    expect(
      chapter({
        occurredAt: "2026-03-01T12:00:00Z",
        occurredEnd: "2026-03-20T12:00:00Z",
      }),
    ).toBe("Mar 2026");
    expect(chapter({ datePrecision: "unknown" })).toBe("Undated");
  });
});

describe("entryRowLabels", () => {
  it("titles an untitled Entry by its date and leaves the date column empty", () => {
    expect(
      entryRowLabels({
        now,
        occurrence: occurrence({ occurredAt: "2026-10-19T12:00:00Z" }),
        title: "  ",
      }),
    ).toEqual({
      date: null,
      dateTime: "2026-10-19",
      title: "Monday, October 19, 2026",
    });
  });

  it("keeps a titled Entry's title and dates it", () => {
    expect(
      entryRowLabels({
        now,
        occurrence: occurrence({ occurredAt: "2026-10-17T12:00:00Z" }),
        title: "Final round",
        year: "hide",
      }),
    ).toEqual({ date: "Oct 17", dateTime: "2026-10-17", title: "Final round" });
  });
});

describe("entryRowDateTime", () => {
  it("matches the recorded precision", () => {
    expect(
      entryRowDateTime(
        occurrence({
          datePrecision: "month",
          occurredAt: "2024-10-01T12:00:00Z",
        }),
      ),
    ).toBe("2024-10");
    expect(
      entryRowDateTime(
        occurrence({
          datePrecision: "year",
          occurredAt: "2019-01-01T12:00:00Z",
        }),
      ),
    ).toBe("2019");
    expect(entryRowDateTime(occurrence({ datePrecision: "unknown" }))).toBe(
      null,
    );
  });
});

describe("entryRowSnippet", () => {
  it("starts near the first match and marks every matched word", () => {
    const body =
      "We drove for hours along the coast before stopping for the night. The old lantern on the porch still worked after the storm, and the lantern light was warm.";
    const parts = entryRowSnippet(body, "Lantern");
    expect(parts[0].text.startsWith("…")).toBe(true);
    expect(parts.filter((part) => part.match).map((part) => part.text)).toEqual(
      ["lantern", "lantern"],
    );
    expect(parts.map((part) => part.text).join("")).toContain(
      "The old lantern on the porch",
    );
  });

  it("starts at the beginning when the match is early or missing", () => {
    expect(entryRowSnippet("A lantern  on\nthe porch.", "lantern")).toEqual([
      { match: false, text: "A " },
      { match: true, text: "lantern" },
      { match: false, text: " on the porch." },
    ]);
    expect(entryRowSnippet("Only the title matched.", "porch")).toEqual([
      { match: false, text: "Only the title matched." },
    ]);
  });

  it("matches text in any script and treats the query as plain text", () => {
    expect(
      entryRowSnippet("今天学习了电弧打火机", "学习").filter(
        (part) => part.match,
      ),
    ).toEqual([{ match: true, text: "学习" }]);
    expect(entryRowSnippet("Cost (approx.) $5", "(approx.)")).toEqual([
      { match: false, text: "Cost " },
      { match: true, text: "(approx.)" },
      { match: false, text: " $5" },
    ]);
  });
});

describe("groupEntryRows", () => {
  it("groups by month, by year for a year-only date, and puts undated last", () => {
    const rows = [
      occurrence({ occurredAt: "2026-10-17T12:00:00Z" }),
      occurrence({ occurredAt: "2026-10-09T12:00:00Z" }),
      occurrence({ occurredAt: "2026-09-28T12:00:00Z" }),
      occurrence({ datePrecision: "year", occurredAt: "2024-01-01T12:00:00Z" }),
      occurrence({ datePrecision: "unknown" }),
    ];
    expect(
      groupEntryRows(rows, (row) => row).map((group) => [
        group.label,
        group.items.length,
      ]),
    ).toEqual([
      ["October 2026", 2],
      ["September 2026", 1],
      ["2024", 1],
      ["Undated", 1],
    ]);
  });

  it("reads the month in the Entry's own zone", () => {
    expect(
      entryRowGroup(
        occurrence({
          datePrecision: "exact",
          occurredAt: "2026-11-01T03:00:00Z",
          occurredTimezone: "America/New_York",
        }),
      ),
    ).toEqual({ key: "2026-10", label: "October 2026" });
  });
});
