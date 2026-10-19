import { describe, expect, it } from "vitest";
import { resolveOccurrenceDraft } from "./occurrence";
import {
  monthLabel,
  nextAllowanceDay,
  parseChapterSuggestion,
  parseReviewContent,
  parseReviewNotice,
  parseReviewPage,
  parseReviewSettings,
  parseReviewYears,
  phaseRangeLabel,
  phasesSpanYears,
  reviewFailureMessage,
  suggestionOccurrenceDraft,
  suggestionSpanLabel,
} from "./review-input";

describe("phase ranges", () => {
  it("names a single month once", () => {
    expect(phaseRangeLabel("2026-03-05", "2026-03-20", false)).toBe(
      "March 2026",
    );
  });

  it("puts the year at the end for a range inside one year", () => {
    expect(phaseRangeLabel("2026-03-05", "2026-06-01", false)).toBe(
      "March - May 2026",
    );
  });

  it("names both years when the range crosses a year or years are asked for", () => {
    expect(phaseRangeLabel("2025-11-05", "2026-02-10", false)).toBe(
      "November 2025 - February 2026",
    );
    expect(phaseRangeLabel("2026-03-05", "2026-06-01", true)).toBe(
      "March 2026 - May 2026",
    );
  });

  it("reads the end as exclusive, so a month boundary does not spill into the next month", () => {
    expect(phaseRangeLabel("2026-03-01", "2026-04-01", false)).toBe(
      "March 2026",
    );
  });

  it("detects a period that spans years", () => {
    expect(
      phasesSpanYears([
        { windowStart: "2025-12-20", windowEnd: "2025-12-21" },
        { windowStart: "2026-01-02", windowEnd: "2026-01-03" },
      ]),
    ).toBe(true);
    expect(
      phasesSpanYears([
        { windowStart: "2026-01-01", windowEnd: "2026-01-02" },
        { windowStart: "2026-12-31", windowEnd: "2027-01-01" },
      ]),
    ).toBe(false);
  });

  it("labels a busiest month", () => {
    expect(monthLabel("2026-03")).toBe("March 2026");
  });
});

describe("suggestions", () => {
  const month = {
    startDate: "2026-03-01",
    startPrecision: "month",
    endDate: "2026-06-01",
    endPrecision: "month",
  } as const;

  it("labels the span, ending now while it is going on", () => {
    expect(suggestionSpanLabel(month)).toBe("Mar 2026 - Jun 2026");
    expect(
      suggestionSpanLabel({
        startDate: "2026-03-01",
        startPrecision: "month",
        endDate: null,
        endPrecision: null,
      }),
    ).toBe("Mar 2026 - now");
  });

  it("builds month dates for a Chapter, and an open end for one still going", () => {
    expect(suggestionOccurrenceDraft(month, "UTC")).toMatchObject({
      precision: "month",
      start: "2026-03",
      end: "2026-06",
      endMode: "date",
    });
    expect(
      suggestionOccurrenceDraft(
        { ...month, endDate: null, endPrecision: null },
        "UTC",
      ),
    ).toMatchObject({ precision: "month", end: "", endMode: "present" });
  });

  it("uses days when either end is a day, ending a month on its last day", () => {
    const draft = suggestionOccurrenceDraft(
      {
        startDate: "2026-03-14",
        startPrecision: "day",
        endDate: "2026-06-01",
        endPrecision: "month",
      },
      "UTC",
    );
    expect(draft).toMatchObject({
      precision: "day",
      start: "2026-03-14",
      end: "2026-06-30",
    });
  });

  it("produces dates the Chapter editor accepts", () => {
    const resolved = resolveOccurrenceDraft(
      suggestionOccurrenceDraft(month, "America/Los_Angeles"),
      undefined,
      true,
    );
    expect(resolved.error).toBeUndefined();
    expect(resolved.value).toMatchObject({
      datePrecision: "month",
      occurredTimezone: "America/Los_Angeles",
    });
    expect(resolved.value?.occurredAt).toBeTruthy();
    expect(resolved.value?.occurredEnd).toBeTruthy();
  });

  it("parses a pending suggestion and rejects one without a name", () => {
    const row = {
      id: "s1",
      name: " Moving ",
      rationale: "You kept returning to it.",
      startDate: "2026-03-01",
      startPrecision: "month",
      endDate: null,
      endPrecision: null,
      entryCount: 5,
      entries: [{ id: "e1", title: "Boxes", datePrecision: "day" }],
    };
    expect(parseChapterSuggestion(row)).toMatchObject({
      name: "Moving",
      entryCount: 5,
      endDate: null,
      entries: [{ id: "e1", title: "Boxes" }],
    });
    expect(parseChapterSuggestion({ ...row, name: null })).toBeNull();
    expect(parseChapterSuggestion(null)).toBeNull();
  });
});

describe("parsing", () => {
  it("reads settings, years, and notices defensively", () => {
    expect(
      parseReviewSettings({
        reviewsEnabled: true,
        chapterSuggestionsEnabled: false,
        disclosureVersion: "2026-10-18",
        revision: 3,
        reviewCount: "4",
        pendingSuggestionCount: 1,
      }),
    ).toEqual({
      reviewsEnabled: true,
      chapterSuggestionsEnabled: false,
      disclosureVersion: "2026-10-18",
      revision: 3,
      reviewCount: 4,
      pendingSuggestionCount: 1,
    });
    expect(parseReviewSettings("nope")).toBeNull();
    expect(
      parseReviewYears([
        { review_year: 2025, entry_count: "12", review_generated_at: null },
        { review_year: "x" },
      ]),
    ).toEqual([{ year: 2025, entryCount: 12, reviewGeneratedAt: null }]);
    expect(
      parseReviewNotice({ subject: "year:2025", kind: "year", year: 2025 }),
    ).toEqual({ subject: "year:2025", kind: "year", year: 2025 });
    expect(
      parseReviewNotice({
        subject: "chapter:c",
        kind: "chapter",
        chapterId: "c",
        title: "",
      }),
    ).toEqual({
      subject: "chapter:c",
      kind: "chapter",
      chapterId: "c",
      title: "This Chapter",
    });
    expect(parseReviewNotice({ kind: "other" })).toBeNull();
  });

  it("reads a review page and drops malformed content", () => {
    const page = parseReviewPage({
      eligibility: {
        status: "eligible",
        entryCount: 6,
        minimum: 5,
        ongoing: true,
      },
      settings: { reviewsEnabled: true, disclosureVersion: "2026-10-18" },
      facts: {
        entryCount: 6,
        firstWindowStart: "2026-03-05",
        lastWindowStart: "2026-04-30",
        firstTimes: [{ id: "f1", title: "Sailing", datePrecision: "day" }],
        topTags: [{ name: "work", count: 3 }, { name: 4 }],
        busiestMonth: { month: "2026-04", count: 4 },
        chapters: [],
      },
      review: {
        id: "r1",
        content: {
          summary: "A busy spring.",
          feelings: {
            overview: "Mostly steady.",
            phases: [
              {
                feeling: "Anxious",
                description: "Waiting.",
                entryIds: ["e1"],
                windowStart: "2026-03-05",
                windowEnd: "2026-03-06",
              },
              { feeling: 3 },
            ],
          },
          themes: [
            { name: "Work", description: "Often.", entryIds: ["e1", "e2"] },
          ],
          quotes: [
            { entryId: "e1", start: 0, end: 5, text: "Hello", why: "Warm." },
            {},
          ],
        },
        language: "zh",
        ongoing: true,
        generatedAt: "2026-10-18T12:00:00Z",
        entriesInPeriod: 6,
        entriesRead: 6,
        trimmedEntries: 0,
        quoteAvailable: [true, false],
        sources: [
          { entryId: "e1", title: "Day", trashed: true, datePrecision: "day" },
        ],
        changes: { newEntries: 1, editedEntries: 2, trashedEntries: 1 },
        job: { status: "ready", error: null, done: 1, total: 1 },
      },
    });
    expect(page?.eligibility).toMatchObject({
      status: "eligible",
      ongoing: true,
    });
    expect(page?.facts).toMatchObject({
      firstDay: "2026-03-05",
      topTags: [{ name: "work", count: 3 }],
      busiestMonth: { month: "2026-04", count: 4 },
    });
    expect(page?.review?.language).toBe("zh");
    expect(page?.review?.content?.feelings.phases).toHaveLength(1);
    expect(page?.review?.content?.quotes).toHaveLength(1);
    expect(page?.review?.sources[0]).toMatchObject({ id: "e1", trashed: true });
    expect(page?.review?.quoteAvailable).toEqual([true, false]);
    expect(parseReviewPage(null)).toBeNull();
    expect(parseReviewContent({ summary: 3 })).toBeNull();
  });

  it("treats an unknown eligibility status as unavailable", () => {
    expect(
      parseReviewPage({ eligibility: { status: "weird" } })?.eligibility.status,
    ).toBe("unavailable");
  });
});

describe("messages", () => {
  it("says when the allowance renews", () => {
    expect(nextAllowanceDay("2026-10-18")).toBe("November 1");
    expect(nextAllowanceDay("2026-12-31")).toBe("January 1");
    expect(reviewFailureMessage("budget_exceeded", "2026-10-18")).toBe(
      "This month's review allowance is used up. It renews on November 1.",
    );
    expect(
      reviewFailureMessage("budget_exceeded", "2026-10-18", true),
    ).toContain("Finished parts are kept for Try again.");
  });

  it("has a plain message for every way a review can fail", () => {
    const codes = [
      "provider_unavailable",
      "rate_limit",
      "review_in_progress",
      "review_limit_reached",
      "review_not_eligible",
      "provider_error",
      "provider_interrupted",
      "generation_interrupted",
      "review_declined",
      "incomplete_generation",
      "invalid_review",
      "ungrounded_review",
      "review_quote_unverified",
      "review_source_deleted",
      "something_new",
      null,
    ];
    for (const code of codes) {
      const message = reviewFailureMessage(code, "2026-10-18");
      expect(message.length).toBeGreaterThan(10);
      expect(message).not.toContain(String.fromCharCode(0x2014));
    }
    expect(reviewFailureMessage("something_new", "2026-10-18")).toBe(
      "Claude couldn't write this review. Your Entries are unchanged. Try again later.",
    );
  });
});
