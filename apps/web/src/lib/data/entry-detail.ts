import type { WikiItemKind } from "./wiki-item";
import type { MilestoneLane, MilestoneShape } from "./milestone";
import { entryDisplayTitle, storedOccurrence } from "./occurrence";

/** The current Entry the Item page shows, as `entry_detail` returns it. */
export type EntryDetail = {
  id: string;
  title: string | null;
  body: string;
  item_kind: WikiItemKind;
  item_subtype: string;
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
  milestone: {
    shape: MilestoneShape;
    lane: MilestoneLane;
    is_first_time: boolean;
  } | null;
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

export function entryDateLabel(
  value: Pick<
    EntryDetail,
    | "occurred_label"
    | "occurred_start"
    | "occurred_end"
    | "occurred_timezone"
    | "date_precision"
  >,
) {
  if (value.occurred_label?.trim()) return value.occurred_label.trim();
  if (!value.occurred_start) return "Unknown";
  let timeZone = value.occurred_timezone || "UTC";
  try {
    new Intl.DateTimeFormat("en-US", { timeZone }).format();
  } catch {
    timeZone = "UTC";
  }
  const options: Intl.DateTimeFormatOptions =
    value.date_precision === "year"
      ? { year: "numeric" }
      : value.date_precision === "month"
        ? { month: "short", year: "numeric" }
        : value.date_precision === "exact"
          ? { dateStyle: "medium", timeStyle: "short" }
          : { dateStyle: "medium" };
  const format = (raw: string) => {
    const date = new Date(raw);
    return Number.isNaN(date.getTime())
      ? "Unknown"
      : new Intl.DateTimeFormat("en-US", { ...options, timeZone }).format(date);
  };
  return (
    format(value.occurred_start) +
    (value.occurred_end ? ` to ${format(value.occurred_end)}` : "")
  );
}
