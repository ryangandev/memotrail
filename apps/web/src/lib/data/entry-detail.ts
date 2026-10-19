import type { WikiItemKind } from "./wiki-item";
import {
  entryDisplayTitle,
  occurrenceDurationLabel,
  occurrenceSpanLabel,
  occurrenceTitle,
  storedOccurrence,
} from "./occurrence";

/** The current Entry the Item page shows, as `entry_detail` returns it. */
export type EntryDetail = {
  id: string;
  title: string | null;
  body: string;
  item_kind: WikiItemKind;
  item_subtype: string;
  is_first_time: boolean;
  revision: number;
  deleted_at: string | null;
  occurred_start: string | null;
  occurred_end: string | null;
  date_precision: string;
  occurred_label: string | null;
  occurred_timezone: string | null;
  metadata?: unknown;
  tags: { id: string; name: string }[];
  locations: {
    location_id: string;
    relationship: "primary" | "photo";
    formatted_address: string | null;
    latitude: number | null;
    longitude: number | null;
  }[];
  links: { target_entry_id: string; relationship: string }[];
};

/** What the Item page calls an item: its title, or its date when it has none. */
export function entryTitle(
  value: Pick<
    EntryDetail,
    | "title"
    | "occurred_label"
    | "occurred_start"
    | "occurred_end"
    | "occurred_timezone"
    | "date_precision"
  >,
) {
  return entryDisplayTitle(
    value.title,
    storedOccurrence({
      datePrecision: value.date_precision,
      occurredEnd: value.occurred_end,
      occurredLabel: value.occurred_label,
      occurredStart: value.occurred_start,
      occurredTimezone: value.occurred_timezone,
    }),
  );
}

/**
 * A Chapter's Date fact: the span it covers and how long that is. A Chapter without a calendar
 * date shows its description alone, never a duration it cannot measure.
 */
export function chapterDateFacts(
  value: Pick<
    EntryDetail,
    | "occurred_label"
    | "occurred_start"
    | "occurred_end"
    | "occurred_timezone"
    | "date_precision"
  >,
  now: Date,
) {
  const occurrence = storedOccurrence({
    datePrecision: value.date_precision,
    occurredEnd: value.occurred_end,
    occurredLabel: value.occurred_label,
    occurredStart: value.occurred_start,
    occurredTimezone: value.occurred_timezone,
  });
  return {
    duration: value.occurred_start
      ? occurrenceDurationLabel(occurrence, now)
      : null,
    span: occurrenceSpanLabel(occurrence),
  };
}

export function validEntryID(id: unknown): id is string {
  return (
    typeof id === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id)
  );
}

/**
 * Whether the Item page's Date fact adds something to its heading. An untitled
 * Entry is already headed by its date, so the fact shows only when it says more:
 * the time of an exact moment, an end the heading leaves out, or a date the
 * heading cannot name.
 */
export function entryDateAddsToTitle(
  value: Pick<
    EntryDetail,
    | "title"
    | "occurred_label"
    | "occurred_start"
    | "occurred_end"
    | "date_precision"
  >,
) {
  if (value.title?.trim()) return true;
  // The heading is the description, or "Undated entry" when nothing is known.
  if (value.occurred_label?.trim() || !value.occurred_start) return false;
  switch (value.date_precision) {
    case "exact":
      return true;
    case "day":
    case "month":
    case "year":
      return Boolean(value.occurred_end);
    case "range":
      return false;
    default:
      return true;
  }
}

type DateFields = Pick<
  EntryDetail,
  | "occurred_label"
  | "occurred_start"
  | "occurred_end"
  | "occurred_timezone"
  | "date_precision"
>;

/**
 * The date in an Entry page's facts line, written out in full as the page reads it:
 * "Tuesday, October 14, 2026", "Saturday, October 3, 2026 at 7:30 AM", "October 2026", or
 * "2026", in the zone it was recorded in. A described date reads as its description.
 */
export function entryDateLabel(value: DateFields) {
  if (value.occurred_label?.trim()) return value.occurred_label.trim();
  const occurrence = undescribed(value);
  const { datePrecision: precision, occurredAt, occurredEnd } = occurrence;
  if (!occurredAt || precision === "unknown" || !readable(occurredAt))
    return "Undated";
  if (precision === "range") return occurrenceTitle(occurrence);
  const point = (iso: string) => {
    const single = { ...occurrence, occurredAt: iso, occurredEnd: null };
    if (precision === "month" || precision === "year")
      return occurrenceTitle(single);
    const day = occurrenceTitle({ ...single, datePrecision: "day" });
    if (precision !== "exact") return day;
    const time = new Intl.DateTimeFormat("en-US", {
      hour: "numeric",
      minute: "2-digit",
      timeZone: occurrence.occurredTimezone,
    }).format(new Date(iso));
    return `${day} at ${time}`;
  };
  return occurredEnd && readable(occurredEnd)
    ? `${point(occurredAt)} to ${point(occurredEnd)}`
    : point(occurredAt);
}

/**
 * A Chapter's span for its page's meta line, at the precision it was recorded: "January 2026 to
 * now", "2017 to 2021", or its description. Null for a Chapter with no date.
 */
export function chapterSpanLabel(value: DateFields) {
  if (value.occurred_label?.trim()) return value.occurred_label.trim();
  const occurrence = undescribed(value);
  const { datePrecision: precision, occurredAt, occurredEnd } = occurrence;
  if (!occurredAt || precision === "unknown" || !readable(occurredAt))
    return null;
  const options: Intl.DateTimeFormatOptions =
    precision === "year"
      ? { year: "numeric" }
      : precision === "month"
        ? { month: "long", year: "numeric" }
        : { day: "numeric", month: "long", year: "numeric" };
  const format = (iso: string) =>
    new Intl.DateTimeFormat("en-US", {
      ...options,
      timeZone: occurrence.occurredTimezone,
    }).format(new Date(iso));
  if (!occurredEnd || !readable(occurredEnd))
    return `${format(occurredAt)} to now`;
  const start = format(occurredAt);
  const end = format(occurredEnd);
  return start === end ? start : `${start} to ${end}`;
}

function undescribed(value: DateFields) {
  return storedOccurrence({
    datePrecision: value.date_precision,
    occurredEnd: value.occurred_end,
    occurredLabel: null,
    occurredStart: value.occurred_start,
    occurredTimezone: value.occurred_timezone,
  });
}

function readable(iso: string) {
  return Number.isFinite(Date.parse(iso));
}
