import { entryRichTextMetadataKey } from "./rich-text";
import type { WikiItemKind } from "./wiki-item";

// Matches the snapshot contract accepted by restore_entry_version.
export const SUPPORTED_HISTORY_SCHEMA = 3;
export const UNSUPPORTED_HISTORY_RESTORE_MESSAGE =
  "This version was saved in a format that cannot be restored. You can still review its recorded content.";

export type HistoryIndexEntry = {
  entry_id: string;
  title: string | null;
  excerpt: string;
  item_kind: WikiItemKind;
  item_subtype: string;
  revision: number;
  is_deleted: boolean;
  version_count: number;
  last_changed: string;
  total_count: number;
};
export type HistorySnapshot = {
  id: string;
  title: string | null;
  body: string;
  item_kind: WikiItemKind;
  item_subtype: string;
  revision: number;
  deleted_at: string | null;
  history_schema?: number;
  occurred_start: string | null;
  occurred_end: string | null;
  date_precision: string;
  occurred_label: string | null;
  occurred_timezone: string | null;
  [key: string]: unknown;
};
export type HistoryVersion = {
  version: number;
  operation: string;
  created_at: string;
  snapshot: HistorySnapshot;
};
export type EntryHistory = {
  current: HistorySnapshot;
  versions: HistoryVersion[];
  total_count: number;
};
export function canRestoreHistorySnapshot(
  snapshot: HistorySnapshot | undefined,
) {
  return snapshot?.history_schema === SUPPORTED_HISTORY_SCHEMA;
}

export const historyFields: Record<string, string> = {
  title: "Title",
  body: "Writing",
  item_kind: "Kind",
  item_subtype: "Subtype",
  occurred_start: "Start date",
  occurred_end: "End date",
  date_precision: "Date precision",
  occurred_label: "Date description",
  occurred_timezone: "Time zone",
  tags: "Tags",
  places: "Location links",
  timeline_items: "Timeline placement",
  home: "Home details",
  vehicle: "Vehicle details",
  goal: "Want to Do details",
  links: "Entry links",
  attachments: "Photos",
  metadata: "Other metadata",
  source_language: "Language",
};
export function historyDifferences(
  current: HistorySnapshot,
  previous: HistorySnapshot,
) {
  return Object.entries(historyFields)
    .filter(
      ([key]) =>
        key in previous &&
        JSON.stringify(comparableHistoryValue(current, key)) !==
          JSON.stringify(comparableHistoryValue(previous, key)),
    )
    .map(([, label]) => label);
}
// Formatting is shown as part of the writing and hidden from the metadata details,
// so a formatting change is a Writing difference rather than Other metadata.
function comparableHistoryValue(snapshot: HistorySnapshot, key: string) {
  const metadata = isRecord(snapshot.metadata) ? snapshot.metadata : null;
  if (key === "body") {
    return [snapshot.body, metadata?.[entryRichTextMetadataKey] ?? null];
  }
  if (key === "metadata" && metadata) {
    const otherMetadata = { ...metadata };
    delete otherMetadata[entryRichTextMetadataKey];
    return otherMetadata;
  }
  return snapshot[key];
}
function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
export function historyTitle(value: {
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
export function validHistoryID(id: unknown): id is string {
  return (
    typeof id === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id)
  );
}
export function validHistoryRestore(
  id: unknown,
  version: unknown,
  revision: unknown,
) {
  return (
    validHistoryID(id) &&
    Number.isSafeInteger(version) &&
    Number(version) > 0 &&
    Number.isSafeInteger(revision) &&
    Number(revision) > Number(version)
  );
}
export function historyPage(value: unknown, max: number) {
  const page = Number(value ?? 1);
  return Number.isSafeInteger(page) && page >= 1 && page <= max ? page : 1;
}

export function historyDateLabel(value: HistorySnapshot) {
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
