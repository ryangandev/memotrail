import {
  entryDisplayTitle,
  validTimezone,
  type Occurrence,
} from "./occurrence";

/**
 * Whether a row's date names its year. Rows under a month heading hide it, since the heading
 * already says it; "auto" hides it for dates in the current year, as Dashboard and Chapter lists
 * read.
 */
export type EntryRowYear = "auto" | "hide" | "show";

export type EntryRowLabels = {
  /** The row's title: the Entry's own, or its date when it has none. */
  title: string;
  /** The date column, or null for an untitled Entry, whose title already is its date. */
  date: string | null;
  /** The machine-readable date for a `<time>` element, when the Entry has a calendar date. */
  dateTime: string | null;
};

/**
 * What an EntryRow shows for an Entry: its title and its date column, at the precision the date
 * was recorded, in the zone it was recorded in. An untitled Entry is titled by its date and
 * leaves the date column empty. A Chapter shows the span it covers.
 */
export function entryRowLabels({
  isChapter = false,
  now,
  occurrence,
  title,
  year = "auto",
}: {
  isChapter?: boolean;
  now?: Date;
  occurrence: Occurrence;
  title: string | null | undefined;
  year?: EntryRowYear;
}): EntryRowLabels {
  const titled = Boolean(title?.trim());
  return {
    date: titled ? entryRowDate(occurrence, { isChapter, now, year }) : null,
    dateTime: entryRowDateTime(occurrence),
    title: entryDisplayTitle(title, occurrence),
  };
}

/**
 * A short date for a row's 112px date column: "Oct 17", "Oct 2024", "2019", "Fall 2025",
 * "Jan 2026 - now" for a Chapter, or "Undated".
 */
export function entryRowDate(
  occurrence: Occurrence,
  {
    isChapter = false,
    now = new Date(),
    year = "auto",
  }: { isChapter?: boolean; now?: Date; year?: EntryRowYear } = {},
): string {
  const label = occurrence.occurredLabel?.trim();
  if (label) return label;
  const start = calendarParts(occurrence.occurredAt, occurrence);
  if (!start || occurrence.datePrecision === "unknown") return "Undated";
  const end = calendarParts(occurrence.occurredEnd, occurrence);

  if (isChapter) {
    const coarse = (parts: CalendarParts) =>
      occurrence.datePrecision === "year"
        ? String(parts.year)
        : `${shortMonths[parts.month - 1]} ${parts.year}`;
    const from = coarse(start);
    if (!end) return `${from} - now`;
    const to = coarse(end);
    return from === to ? from : `${from} - ${to}`;
  }

  if (occurrence.datePrecision === "year") return String(start.year);
  if (
    occurrence.datePrecision === "month" ||
    occurrence.datePrecision === "approximate" ||
    occurrence.datePrecision === "age"
  ) {
    return `${shortMonths[start.month - 1]} ${start.year}`;
  }

  const showYear =
    year === "show" ||
    (year === "auto" &&
      (start.year !== calendarParts(now.toISOString(), occurrence)?.year ||
        (end !== null && end.year !== start.year)));
  const day = (parts: CalendarParts) =>
    `${shortMonths[parts.month - 1]} ${parts.day}`;

  if (occurrence.datePrecision !== "range") {
    return showYear ? `${day(start)}, ${start.year}` : day(start);
  }
  if (!end) {
    return `${showYear ? `${day(start)}, ${start.year}` : day(start)} onward`;
  }
  if (end.year !== start.year) {
    return `${day(start)}, ${start.year} - ${day(end)}, ${end.year}`;
  }
  const span =
    end.month === start.month
      ? end.day === start.day
        ? day(start)
        : `${day(start)} - ${end.day}`
      : `${day(start)} - ${day(end)}`;
  return showYear ? `${span}, ${start.year}` : span;
}

/** A `<time>` element's dateTime at the Entry's precision, such as "2026-10" for a month. */
export function entryRowDateTime(occurrence: Occurrence): string | null {
  const start = calendarParts(occurrence.occurredAt, occurrence);
  if (!start || occurrence.datePrecision === "unknown") return null;
  const yyyy = String(start.year).padStart(4, "0");
  const mm = String(start.month).padStart(2, "0");
  const dd = String(start.day).padStart(2, "0");
  if (occurrence.datePrecision === "year") return yyyy;
  if (occurrence.datePrecision === "month") return `${yyyy}-${mm}`;
  if (occurrence.datePrecision === "exact" && occurrence.occurredAt) {
    return new Date(occurrence.occurredAt).toISOString();
  }
  return `${yyyy}-${mm}-${dd}`;
}

export type EntryRowGroupKey = { key: string; label: string };

/**
 * The heading a row sits under in a list ordered by life date: its month, its year for a date
 * known only to the year, or Undated.
 */
export function entryRowGroup(occurrence: Occurrence): EntryRowGroupKey {
  const start = calendarParts(occurrence.occurredAt, occurrence);
  if (!start || occurrence.datePrecision === "unknown") {
    return { key: "undated", label: "Undated" };
  }
  if (occurrence.datePrecision === "year") {
    return { key: String(start.year), label: String(start.year) };
  }
  return {
    key: `${start.year}-${String(start.month).padStart(2, "0")}`,
    label: `${longMonths[start.month - 1]} ${start.year}`,
  };
}

/**
 * Splits rows already ordered by life date into runs that share a heading. A heading repeats
 * only when the order returns to it, so each run keeps the order it was given.
 */
export function groupEntryRows<Item>(
  items: readonly Item[],
  occurrenceOf: (item: Item) => Occurrence,
): (EntryRowGroupKey & { items: Item[] })[] {
  const groups: (EntryRowGroupKey & { items: Item[] })[] = [];
  for (const item of items) {
    const group = entryRowGroup(occurrenceOf(item));
    const last = groups.at(-1);
    if (last && last.key === group.key) last.items.push(item);
    else groups.push({ ...group, items: [item] });
  }
  return groups;
}

/** A run of excerpt text, marked when it matched the search. */
export type EntryRowSnippetPart = { match: boolean; text: string };

const snippetLead = 48;
const snippetLength = 220;

/**
 * One line of an Entry's writing for a search result: the text around the first word that
 * matched, with every matched word marked. Text without a match starts at the beginning.
 */
export function entryRowSnippet(
  text: string,
  query: string,
): EntryRowSnippetPart[] {
  const compact = text.replace(/\s+/g, " ").trim();
  if (!compact) return [];
  const terms = [
    ...new Set(
      query
        .trim()
        .split(/\s+/)
        .filter(Boolean)
        .map((term) => term.toLocaleLowerCase()),
    ),
  ].sort((left, right) => right.length - left.length);
  const pattern = terms.length
    ? new RegExp(terms.map(escapeRegExp).join("|"), "giu")
    : null;

  const first = pattern ? compact.search(pattern) : -1;
  let start = 0;
  if (first > snippetLead) {
    const space = compact.lastIndexOf(" ", first - snippetLead);
    start = space >= 0 ? space + 1 : first - snippetLead;
  }
  const characters = Array.from(compact.slice(start));
  const clipped = characters.length > snippetLength;
  const shown = clipped
    ? characters.slice(0, snippetLength).join("").trimEnd()
    : characters.join("");

  const parts: EntryRowSnippetPart[] = [];
  const push = (part: string, match: boolean) => {
    const last = parts.at(-1);
    if (!part) return;
    if (last && !last.match && !match) last.text += part;
    else parts.push({ match, text: part });
  };
  if (start > 0) push("…", false);
  let cursor = 0;
  if (pattern) {
    for (const found of shown.matchAll(pattern)) {
      push(shown.slice(cursor, found.index), false);
      push(found[0], true);
      cursor = found.index + found[0].length;
    }
  }
  push(shown.slice(cursor), false);
  if (clipped) push("…", false);
  return parts;
}

function escapeRegExp(value: string) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

type CalendarParts = { day: number; month: number; year: number };

function calendarParts(
  iso: string | null,
  occurrence: Occurrence,
): CalendarParts | null {
  if (!iso || !Number.isFinite(Date.parse(iso))) return null;
  const parts = new Intl.DateTimeFormat("en-US", {
    day: "numeric",
    month: "numeric",
    timeZone: validTimezone(occurrence.occurredTimezone)
      ? occurrence.occurredTimezone
      : "UTC",
    year: "numeric",
  }).formatToParts(new Date(iso));
  const part = (type: Intl.DateTimeFormatPartTypes) =>
    Number(parts.find((candidate) => candidate.type === type)?.value);
  return { day: part("day"), month: part("month"), year: part("year") };
}

const shortMonths = [
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec",
];

const longMonths = [
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December",
];
