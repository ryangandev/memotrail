import type { ReviewContent } from "@/lib/ai/review/grounding";
import {
  occurrenceLabel,
  type OccurrenceDraft,
  type OccurrencePrecision,
} from "./occurrence";

/**
 * What the pages and components know about reviews, Chapter suggestions, and the settings
 * behind them. This file has no server-only code so client components can use it too.
 */

export type ReviewEligibilityStatus =
  "eligible" | "too_few_entries" | "unanchored" | "not_over" | "unavailable";

export type ReviewEligibility = {
  status: ReviewEligibilityStatus;
  entryCount: number;
  minimum: number;
  /** A Chapter that has not ended: the review is a review so far. */
  ongoing: boolean;
};

export type ReviewEntryRef = {
  id: string;
  title: string;
  occurredStart: string | null;
  occurredEnd: string | null;
  occurredLabel: string | null;
  occurredTimezone: string;
  datePrecision: OccurrencePrecision;
};

export type ReviewFacts = {
  entryCount: number;
  /** The first and last day an Entry in the period stands for, or null when it has none. */
  firstDay: string | null;
  lastDay: string | null;
  firstTimes: ReviewEntryRef[];
  topTags: { name: string; count: number }[];
  busiestMonth: { month: string; count: number } | null;
  /** The Chapters that overlap a year; empty for a Chapter. */
  chapters: ReviewEntryRef[];
};

export type ReviewSource = ReviewEntryRef & { trashed: boolean };

export type ReviewJob = {
  status: "idle" | "generating" | "ready" | "failed";
  error: string | null;
  done: number;
  total: number;
};

export type StoredReview = {
  id: string;
  content: ReviewContent | null;
  model: string | null;
  language: "en" | "zh";
  ongoing: boolean;
  generatedAt: string | null;
  entriesInPeriod: number;
  entriesRead: number;
  trimmedEntries: number;
  /** Whether each quote, in order, may be shown now. */
  quoteAvailable: boolean[];
  sources: ReviewSource[];
  changes: {
    newEntries: number;
    editedEntries: number;
    trashedEntries: number;
  };
  job: ReviewJob;
};

export type ReviewPageData = {
  eligibility: ReviewEligibility;
  settings: { reviewsEnabled: boolean; disclosureVersion: string | null };
  facts: ReviewFacts | null;
  review: StoredReview | null;
};

export type ReviewSettings = {
  reviewsEnabled: boolean;
  chapterSuggestionsEnabled: boolean;
  disclosureVersion: string | null;
  revision: number;
  reviewCount: number;
  pendingSuggestionCount: number;
};

export type ReviewYear = {
  year: number;
  entryCount: number;
  reviewGeneratedAt: string | null;
};

export type ReviewNotice =
  | { subject: string; kind: "year"; year: number }
  | { subject: string; kind: "chapter"; chapterId: string; title: string };

export type ChapterSuggestion = {
  id: string;
  name: string;
  rationale: string;
  startDate: string;
  startPrecision: "day" | "month";
  endDate: string | null;
  endPrecision: "day" | "month" | null;
  entryCount: number;
  entries: ReviewEntryRef[];
};

type Row = Record<string, unknown>;
const isRow = (value: unknown): value is Row =>
  typeof value === "object" && value !== null && !Array.isArray(value);
const text = (value: unknown) => (typeof value === "string" ? value : null);
const count = (value: unknown) =>
  typeof value === "number" && Number.isFinite(value) && value >= 0
    ? Math.floor(value)
    : typeof value === "string" && /^\d+$/.test(value)
      ? Number(value)
      : 0;

const PRECISIONS = [
  "exact",
  "day",
  "month",
  "year",
  "approximate",
  "age",
  "range",
  "unknown",
] as const;

function entryRef(value: unknown): ReviewEntryRef | null {
  if (!isRow(value)) return null;
  const id = text(value.id ?? value.entryId);
  if (!id) return null;
  const precision = text(value.datePrecision);
  return {
    id,
    title: text(value.title)?.trim() ?? "",
    occurredStart: text(value.occurredStart),
    occurredEnd: text(value.occurredEnd),
    occurredLabel: text(value.occurredLabel),
    occurredTimezone: text(value.occurredTimezone) ?? "UTC",
    datePrecision: (PRECISIONS as readonly string[]).includes(precision ?? "")
      ? (precision as OccurrencePrecision)
      : "unknown",
  };
}

function entryRefs(value: unknown) {
  return Array.isArray(value)
    ? value.flatMap((item) => {
        const ref = entryRef(item);
        return ref ? [ref] : [];
      })
    : [];
}

function parseEligibility(value: unknown): ReviewEligibility {
  const row = isRow(value) ? value : {};
  const statuses: readonly string[] = [
    "eligible",
    "too_few_entries",
    "unanchored",
    "not_over",
    "unavailable",
  ];
  const status = text(row.status);
  return {
    status: (statuses.includes(status ?? "")
      ? status
      : "unavailable") as ReviewEligibilityStatus,
    entryCount: count(row.entryCount),
    minimum: count(row.minimum) || 5,
    ongoing: row.ongoing === true,
  };
}

function parseFacts(value: unknown): ReviewFacts | null {
  if (!isRow(value)) return null;
  const busiest = isRow(value.busiestMonth) ? value.busiestMonth : null;
  return {
    entryCount: count(value.entryCount),
    firstDay: text(value.firstWindowStart),
    lastDay: text(value.lastWindowStart),
    firstTimes: entryRefs(value.firstTimes),
    topTags: Array.isArray(value.topTags)
      ? value.topTags.flatMap((tag) =>
          isRow(tag) && typeof tag.name === "string"
            ? [{ name: tag.name, count: count(tag.count) }]
            : [],
        )
      : [],
    busiestMonth:
      busiest &&
      typeof busiest.month === "string" &&
      /^\d{4}-\d{2}$/.test(busiest.month)
        ? { month: busiest.month, count: count(busiest.count) }
        : null,
    chapters: entryRefs(value.chapters),
  };
}

function stringArray(value: unknown) {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string")
    : [];
}

/** The stored content, read defensively; anything that does not have the expected shape is dropped. */
export function parseReviewContent(value: unknown): ReviewContent | null {
  if (
    !isRow(value) ||
    typeof value.summary !== "string" ||
    !isRow(value.feelings)
  )
    return null;
  const phases = Array.isArray(value.feelings.phases)
    ? value.feelings.phases
    : [];
  const themes = Array.isArray(value.themes) ? value.themes : [];
  const quotes = Array.isArray(value.quotes) ? value.quotes : [];
  return {
    summary: value.summary,
    feelings: {
      overview: text(value.feelings.overview) ?? "",
      phases: phases.flatMap((phase) =>
        isRow(phase) &&
        typeof phase.feeling === "string" &&
        typeof phase.description === "string"
          ? [
              {
                feeling: phase.feeling,
                description: phase.description,
                entryIds: stringArray(phase.entryIds),
                windowStart: text(phase.windowStart) ?? "",
                windowEnd: text(phase.windowEnd) ?? "",
              },
            ]
          : [],
      ),
    },
    themes: themes.flatMap((theme) =>
      isRow(theme) &&
      typeof theme.name === "string" &&
      typeof theme.description === "string"
        ? [
            {
              name: theme.name,
              description: theme.description,
              entryIds: stringArray(theme.entryIds),
            },
          ]
        : [],
    ),
    quotes: quotes.flatMap((quote) =>
      isRow(quote) &&
      typeof quote.entryId === "string" &&
      typeof quote.text === "string" &&
      typeof quote.why === "string" &&
      Number.isInteger(quote.start) &&
      Number.isInteger(quote.end)
        ? [
            {
              entryId: quote.entryId,
              start: quote.start as number,
              end: quote.end as number,
              text: quote.text,
              why: quote.why,
            },
          ]
        : [],
    ),
  };
}

function parseStoredReview(value: unknown): StoredReview | null {
  if (!isRow(value) || typeof value.id !== "string") return null;
  const job = isRow(value.job) ? value.job : {};
  const status = text(job.status);
  const changes = isRow(value.changes) ? value.changes : {};
  return {
    id: value.id,
    content: parseReviewContent(value.content),
    model: text(value.model),
    language: value.language === "zh" ? "zh" : "en",
    ongoing: value.ongoing === true,
    generatedAt: text(value.generatedAt),
    entriesInPeriod: count(value.entriesInPeriod),
    entriesRead: count(value.entriesRead),
    trimmedEntries: count(value.trimmedEntries),
    quoteAvailable: Array.isArray(value.quoteAvailable)
      ? value.quoteAvailable.map((item) => item === true)
      : [],
    sources: Array.isArray(value.sources)
      ? value.sources.flatMap((source) => {
          const ref = entryRef(source);
          return ref && isRow(source)
            ? [{ ...ref, trashed: source.trashed === true }]
            : [];
        })
      : [],
    changes: {
      newEntries: count(changes.newEntries),
      editedEntries: count(changes.editedEntries),
      trashedEntries: count(changes.trashedEntries),
    },
    job: {
      status: (["generating", "ready", "failed", "idle"].includes(status ?? "")
        ? status
        : "idle") as ReviewJob["status"],
      error: text(job.error),
      done: count(job.done),
      total: count(job.total),
    },
  };
}

export function parseReviewPage(value: unknown): ReviewPageData | null {
  if (!isRow(value)) return null;
  const settings = isRow(value.settings) ? value.settings : {};
  return {
    eligibility: parseEligibility(value.eligibility),
    settings: {
      reviewsEnabled: settings.reviewsEnabled === true,
      disclosureVersion: text(settings.disclosureVersion),
    },
    facts: parseFacts(value.facts),
    review: parseStoredReview(value.review),
  };
}

export function parseReviewSettings(value: unknown): ReviewSettings | null {
  if (!isRow(value)) return null;
  return {
    reviewsEnabled: value.reviewsEnabled === true,
    chapterSuggestionsEnabled: value.chapterSuggestionsEnabled === true,
    disclosureVersion: text(value.disclosureVersion),
    revision: count(value.revision),
    reviewCount: count(value.reviewCount),
    pendingSuggestionCount: count(value.pendingSuggestionCount),
  };
}

export function parseReviewYears(value: unknown): ReviewYear[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((row) =>
    isRow(row) && Number.isInteger(row.review_year)
      ? [
          {
            year: row.review_year as number,
            entryCount: count(row.entry_count),
            reviewGeneratedAt: text(row.review_generated_at),
          },
        ]
      : [],
  );
}

export function parseReviewNotice(value: unknown): ReviewNotice | null {
  if (!isRow(value) || typeof value.subject !== "string") return null;
  if (value.kind === "year" && Number.isInteger(value.year))
    return { subject: value.subject, kind: "year", year: value.year as number };
  if (value.kind === "chapter" && typeof value.chapterId === "string")
    return {
      subject: value.subject,
      kind: "chapter",
      chapterId: value.chapterId,
      title: text(value.title)?.trim() || "This Chapter",
    };
  return null;
}

export function parseChapterSuggestion(
  value: unknown,
): ChapterSuggestion | null {
  if (!isRow(value) || typeof value.id !== "string") return null;
  const name = text(value.name)?.trim();
  const rationale = text(value.rationale)?.trim();
  const startDate = text(value.startDate);
  const startPrecision =
    value.startPrecision === "day"
      ? "day"
      : value.startPrecision === "month"
        ? "month"
        : null;
  if (!name || !rationale || !startDate || !startPrecision) return null;
  const endDate = text(value.endDate);
  const endPrecision =
    value.endPrecision === "day"
      ? "day"
      : value.endPrecision === "month"
        ? "month"
        : null;
  return {
    id: value.id,
    name,
    rationale,
    startDate,
    startPrecision,
    endDate: endDate && endPrecision ? endDate : null,
    endPrecision: endDate && endPrecision ? endPrecision : null,
    entryCount: count(value.entryCount),
    entries: entryRefs(value.entries),
  };
}

const MONTH_NAMES = new Intl.DateTimeFormat("en-US", {
  month: "long",
  timeZone: "UTC",
});
const MONTH_YEAR = new Intl.DateTimeFormat("en-US", {
  month: "long",
  year: "numeric",
  timeZone: "UTC",
});
const SHORT_MONTH_YEAR = new Intl.DateTimeFormat("en-US", {
  month: "short",
  year: "numeric",
  timeZone: "UTC",
});

function utc(date: string) {
  return new Date(`${date.slice(0, 10)}T00:00:00Z`);
}

/** "March 2026" from a "YYYY-MM" busiest month. */
export function monthLabel(month: string) {
  return MONTH_YEAR.format(utc(`${month}-01`));
}

/**
 * The months a phase covers, from the first day of its earliest Entry to the day before its
 * exclusive end. A period inside one year names the year once, at the end ("March - May 2026").
 */
export function phaseRangeLabel(
  windowStart: string,
  windowEnd: string,
  withYears: boolean,
) {
  if (!/^\d{4}-\d{2}-\d{2}/.test(windowStart)) return "";
  const first = utc(windowStart);
  const last = /^\d{4}-\d{2}-\d{2}/.test(windowEnd)
    ? utc(windowEnd)
    : new Date(first);
  last.setUTCDate(last.getUTCDate() - 1);
  const end = last < first ? first : last;
  const sameMonth =
    first.getUTCFullYear() === end.getUTCFullYear() &&
    first.getUTCMonth() === end.getUTCMonth();
  if (sameMonth) return MONTH_YEAR.format(first);
  if (withYears || first.getUTCFullYear() !== end.getUTCFullYear())
    return `${MONTH_YEAR.format(first)} - ${MONTH_YEAR.format(end)}`;
  return `${MONTH_NAMES.format(first)} - ${MONTH_YEAR.format(end)}`;
}

/** Whether a review's phases cross a year boundary, so every range names its years. */
export function phasesSpanYears(
  phases: readonly { windowStart: string; windowEnd: string }[],
) {
  const years = new Set<number>();
  for (const phase of phases) {
    if (/^\d{4}/.test(phase.windowStart))
      years.add(Number(phase.windowStart.slice(0, 4)));
    if (/^\d{4}/.test(phase.windowEnd)) {
      const end = utc(phase.windowEnd);
      end.setUTCDate(end.getUTCDate() - 1);
      years.add(end.getUTCFullYear());
    }
  }
  return years.size > 1;
}

/** "Nov 2025 - Jan 2026" style span for a suggestion, ending "now" while it is going on. */
export function suggestionSpanLabel(
  suggestion: Pick<
    ChapterSuggestion,
    "startDate" | "startPrecision" | "endDate" | "endPrecision"
  >,
) {
  const point = (date: string, precision: "day" | "month") =>
    precision === "month"
      ? SHORT_MONTH_YEAR.format(utc(date))
      : occurrenceLabel({
          occurredAt: `${date}T12:00:00Z`,
          occurredEnd: null,
          occurredLabel: null,
          occurredTimezone: "UTC",
          datePrecision: "day",
        });
  const start = point(suggestion.startDate, suggestion.startPrecision);
  const end =
    suggestion.endDate && suggestion.endPrecision
      ? point(suggestion.endDate, suggestion.endPrecision)
      : "now";
  return `${start} - ${end}`;
}

/** The date fields a new Chapter starts with when someone chooses Review and add. */
export function suggestionOccurrenceDraft(
  suggestion: Pick<
    ChapterSuggestion,
    "startDate" | "startPrecision" | "endDate" | "endPrecision"
  >,
  timezone: string,
): OccurrenceDraft {
  const byDay =
    suggestion.startPrecision === "day" || suggestion.endPrecision === "day";
  const startOf = (date: string) => (byDay ? date : date.slice(0, 7));
  const endOf = (date: string, precision: "day" | "month") => {
    if (!byDay) return date.slice(0, 7);
    if (precision === "day") return date;
    // A month used as the end of a day-precision Chapter ends on its last day.
    const last = utc(date);
    last.setUTCMonth(last.getUTCMonth() + 1, 0);
    return last.toISOString().slice(0, 10);
  };
  return {
    precision: byDay ? "day" : "month",
    start: startOf(suggestion.startDate),
    end:
      suggestion.endDate && suggestion.endPrecision
        ? endOf(suggestion.endDate, suggestion.endPrecision)
        : "",
    endMode: suggestion.endDate ? "date" : "present",
    label: "",
    timezone,
  };
}

const NEXT_MONTH = new Intl.DateTimeFormat("en-US", {
  month: "long",
  day: "numeric",
  timeZone: "UTC",
});

/** The first day of next month, such as "November 1", for the message about an used-up allowance. */
export function nextAllowanceDay(localDate: string) {
  const [year, month] = localDate.split("-").map(Number);
  return NEXT_MONTH.format(new Date(Date.UTC(year, month, 1)));
}

const GENERIC =
  "Claude couldn't write this review. Your Entries are unchanged. Try again later.";
const INTERRUPTED =
  "The review stopped before it finished. Finished parts are kept; Try again continues from there.";
const UNCHECKED =
  "Claude's review couldn't be checked against your Entries, so it isn't shown. Try again.";

/**
 * What to tell the person when a review could not be made, from the code the job or the request
 * ended with. `localDate` is today for the person, used to say when the allowance renews.
 */
export function reviewFailureMessage(
  code: string | null | undefined,
  localDate: string,
  midJob = false,
) {
  switch (code) {
    case "provider_unavailable":
    case "ai_paused":
    case "review_unavailable":
      return "Reviews aren't available on this server right now. Your Entries are unchanged.";
    case "budget_exceeded":
      return `This month's review allowance is used up. It renews on ${nextAllowanceDay(localDate)}.${
        midJob ? " Finished parts are kept for Try again." : ""
      }`;
    case "rate_limit":
      return "Too many AI requests in the last hour. Try again later.";
    case "review_in_progress":
      return "Another review is being written. Try again when it finishes.";
    case "review_limit_reached":
      return "You've made this review three times today. Try again tomorrow.";
    case "review_not_eligible":
      return "This review can't be made right now. Reload to see its current state.";
    case "review_consent_required":
    case "ai_disabled":
      return "Reviews are turned off. Turn them on in Settings to make a review.";
    case "provider_error":
    case "provider_authentication":
      return GENERIC;
    case "provider_interrupted":
    case "generation_interrupted":
    case "generation_failed":
      return INTERRUPTED;
    case "review_declined":
      return "Claude declined to write a review of this period. Your Entries are unchanged.";
    case "incomplete_generation":
      return "The review was too long to finish. Try again.";
    case "invalid_review":
    case "ungrounded_review":
    case "review_quote_unverified":
      return UNCHECKED;
    case "review_source_deleted":
      return "An Entry this review was reading was deleted forever. Make the review again.";
    default:
      return GENERIC;
  }
}
