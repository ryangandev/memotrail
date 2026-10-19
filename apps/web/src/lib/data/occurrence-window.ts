import { validTimezone, type Occurrence } from "./occurrence";

/**
 * The calendar days a dated Entry or Chapter covers, as ISO dates in the zone it was recorded in.
 * `last` is inclusive, and null for a span that is still going.
 */
export type OccurrenceWindow = { first: string; last: string | null };

/**
 * The days an occurrence covers, matching `wiki_item_occurrence_window` in the database: a year or
 * month date covers the whole year or month, a range or ongoing Chapter without an end is open, and
 * a date that is unknown or has no start covers nothing. `ongoing` is true for a Chapter, whose
 * missing end means it continues, and false for an Entry, whose missing end means one moment.
 */
export function occurrenceWindow(
  occurrence: Occurrence,
  ongoing: boolean,
): OccurrenceWindow | null {
  const { datePrecision: precision, occurredAt, occurredEnd } = occurrence;
  if (!occurredAt || precision === "unknown") return null;
  const start = localDate(occurredAt, occurrence.occurredTimezone);
  if (!start) return null;
  const first =
    precision === "year"
      ? `${start.slice(0, 4)}-01-01`
      : precision === "month"
        ? `${start.slice(0, 7)}-01`
        : start;
  if (!occurredEnd && (precision === "range" || ongoing)) {
    return { first, last: null };
  }
  const end = occurredEnd
    ? localDate(occurredEnd, occurrence.occurredTimezone)
    : start;
  if (!end) return null;
  const last =
    precision === "year"
      ? `${end.slice(0, 4)}-12-31`
      : precision === "month"
        ? lastDayOfMonth(end)
        : end;
  return last < first ? null : { first, last };
}

/** Whether every day of `inner` falls inside `outer`, as the database's `@>` decides it. */
export function windowContains(
  outer: OccurrenceWindow,
  inner: OccurrenceWindow,
): boolean {
  if (inner.first < outer.first) return false;
  if (outer.last === null) return true;
  return inner.last !== null && inner.last <= outer.last;
}

/** A Chapter beside another: the window it shares days with, and whether it lies inside it. */
export type ChapterRelation = "inside" | "overlaps";

/** How another Chapter sits against this one: inside it, or only sharing some of its days. */
export function chapterRelation(
  chapter: Occurrence,
  other: Occurrence,
): ChapterRelation {
  const outer = occurrenceWindow(chapter, true);
  const inner = occurrenceWindow(other, true);
  return outer && inner && windowContains(outer, inner) ? "inside" : "overlaps";
}

/** A Chapter an Entry could belong to. */
export type ChapterCandidate = { id: string; occurrence: Occurrence };

/**
 * The Chapters whose days hold every day of an Entry, innermost first: the one that started
 * latest, then the one that ends soonest. This is the rule `chapter_entries` lists Entries by.
 */
export function chaptersContaining<Candidate extends ChapterCandidate>(
  entry: Occurrence,
  chapters: readonly Candidate[],
): Candidate[] {
  const days = occurrenceWindow(entry, false);
  if (!days) return [];
  return chapters
    .map((chapter) => ({
      chapter,
      window: occurrenceWindow(chapter.occurrence, true),
    }))
    .filter(
      (item): item is { chapter: Candidate; window: OccurrenceWindow } =>
        item.window !== null && windowContains(item.window, days),
    )
    .sort(
      (left, right) =>
        right.window.first.localeCompare(left.window.first) ||
        (left.window.last ?? "9999-12-31").localeCompare(
          right.window.last ?? "9999-12-31",
        ),
    )
    .map((item) => item.chapter);
}

/** The ISO date of a moment in a zone, or null when the moment cannot be read. */
export function localDate(iso: string, timezone: string): string | null {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return null;
  const parts = new Intl.DateTimeFormat("en-CA", {
    day: "2-digit",
    month: "2-digit",
    timeZone: validTimezone(timezone) ? timezone : "UTC",
    year: "numeric",
  }).formatToParts(date);
  const part = (type: Intl.DateTimeFormatPartTypes) =>
    parts.find((candidate) => candidate.type === type)?.value ?? "";
  return `${part("year").padStart(4, "0")}-${part("month")}-${part("day")}`;
}

function lastDayOfMonth(isoDate: string) {
  const year = Number(isoDate.slice(0, 4));
  const month = Number(isoDate.slice(5, 7));
  const day = new Date(Date.UTC(year, month, 0)).getUTCDate();
  return `${isoDate.slice(0, 7)}-${String(day).padStart(2, "0")}`;
}
