import "server-only";

import { getAuthenticatedContext } from "./inbox";
import { isWikiItemKind, wikiEntryHref, type WikiItemKind } from "./wiki-item";

export const wikiItemsPageSize = 12;

export type WikiItemSummary = {
  datePrecision: string;
  excerpt: string;
  id: string;
  isFirstTime: boolean;
  itemKind: WikiItemKind;
  itemSubtype: string;
  occurredEnd: string | null;
  occurredLabel: string | null;
  occurredStart: string | null;
  occurredTimezone: string | null;
  /** The stored title, blank when the item has none. */
  title: string;
  totalCount: number;
  updatedAt: string;
};

type WikiItemRow = {
  canonical_item_id: string;
  date_precision: string;
  excerpt: string;
  is_first_time: boolean;
  item_id: string;
  item_kind: WikiItemKind;
  item_subtype: string;
  occurred_end: string | null;
  occurred_label: string | null;
  occurred_start: string | null;
  occurred_timezone: string | null;
  title: string;
  total_count: number | string;
  updated_at: string;
};

/**
 * One page of every Entry in Library, newest first by the date it happened, with undated Entries
 * last.
 */
export async function getWikiItemsWorkspace(page: number) {
  const context = await getAuthenticatedContext();
  if (!context) return null;

  const result = await context.client.rpc("wiki_items_workspace", {
    p_item_kinds: [],
    p_item_subtypes: [],
    p_limit: wikiItemsPageSize,
    p_offset: (page - 1) * wikiItemsPageSize,
    p_query: "",
  });
  const items = result.error ? null : parseWikiItemRows(result.data);

  return {
    error:
      result.error || !items
        ? "Library could not load. Refresh to try again."
        : null,
    items: items ?? [],
  };
}

export function parseWikiItemRows(value: unknown): WikiItemSummary[] | null {
  if (!Array.isArray(value)) return null;
  const items: WikiItemSummary[] = [];
  for (const candidate of value) {
    if (!isWikiItemRow(candidate)) return null;
    items.push({
      datePrecision: candidate.date_precision,
      excerpt: candidate.excerpt,
      id: candidate.canonical_item_id,
      isFirstTime: candidate.is_first_time,
      itemKind: candidate.item_kind,
      itemSubtype: candidate.item_subtype,
      occurredEnd: candidate.occurred_end,
      occurredLabel: candidate.occurred_label,
      occurredStart: candidate.occurred_start,
      occurredTimezone: candidate.occurred_timezone,
      title: candidate.title,
      totalCount: Number(candidate.total_count),
      updatedAt: candidate.updated_at,
    });
  }
  return items;
}

export function wikiItemHref(item: WikiItemSummary) {
  return wikiEntryHref(item);
}

export function wikiItemsPage(value: unknown) {
  const page = Number(value ?? 1);
  return Number.isSafeInteger(page) && page >= 1 && page <= 2_778 ? page : 1;
}

function isWikiItemRow(value: unknown): value is WikiItemRow {
  if (!value || typeof value !== "object") return false;
  const row = value as Partial<WikiItemRow>;
  return (
    typeof row.canonical_item_id === "string" &&
    typeof row.item_id === "string" &&
    typeof row.is_first_time === "boolean" &&
    isWikiItemKind(row.item_kind) &&
    typeof row.item_subtype === "string" &&
    typeof row.title === "string" &&
    typeof row.excerpt === "string" &&
    typeof row.date_precision === "string" &&
    (row.occurred_start === null || typeof row.occurred_start === "string") &&
    (row.occurred_end === null || typeof row.occurred_end === "string") &&
    (row.occurred_label === null || typeof row.occurred_label === "string") &&
    (row.occurred_timezone === null ||
      typeof row.occurred_timezone === "string") &&
    typeof row.updated_at === "string" &&
    Number.isFinite(Number(row.total_count))
  );
}
