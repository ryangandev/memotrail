import type { WikiItemKind } from "./wiki-item";

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
  places: { place_id: string; relationship: string; name: string | null }[];
  timeline_items: {
    track_id: string;
    timeline_kind: string;
    track_name: string;
  }[];
  links: { target_entry_id: string; relationship: string }[];
};

export function entryTitle(value: {
  title: string | null;
  body?: string;
  excerpt?: string;
}) {
  return (
    value.title?.trim() ||
    (value.body ?? value.excerpt ?? "").trim().slice(0, 80) ||
    "Untitled item"
  );
}

export function validEntryID(id: unknown): id is string {
  return (
    typeof id === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id)
  );
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
