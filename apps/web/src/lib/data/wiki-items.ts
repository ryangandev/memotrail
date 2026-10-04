import "server-only";

import { getAuthenticatedContext } from "./inbox";
import { isWikiItemKind, wikiEntryHref, type WikiItemKind } from "./wiki-item";

export const wikiItemsPageSize = 12;

export type WikiItemSummary = {
  excerpt: string;
  id: string;
  itemKind: WikiItemKind;
  itemSubtype: string;
  occurredEnd: string | null;
  occurredStart: string | null;
  recordId: string;
  recordSource: "entry";
  title: string;
  totalCount: number;
  updatedAt: string;
};

type WikiItemRow = {
  canonical_item_id: string;
  excerpt: string;
  item_id: string;
  item_kind: WikiItemKind;
  item_subtype: string;
  occurred_end: string | null;
  occurred_start: string | null;
  record_source: "entry";
  title: string;
  total_count: number | string;
  updated_at: string;
};

export async function getWikiItemsWorkspace(input: {
  itemKind: WikiItemKind | null;
  needsOrganizing: boolean;
  page: number;
  query: string;
}) {
  const context = await getAuthenticatedContext();
  if (!context) return null;

  const page = (needsOrganizing: boolean, limit: number, offset: number) =>
    context.client.rpc("wiki_items_workspace", {
      p_item_kinds: input.itemKind ? [input.itemKind] : [],
      p_item_subtypes: [],
      p_limit: limit,
      p_needs_organizing: needsOrganizing,
      p_offset: offset,
      p_query: input.query,
    });
  // The needs organizing view counts its own page; the full list asks for
  // one matching row only to learn how many Entries still need organizing.
  const [result, needsOrganizing] = await Promise.all([
    page(
      input.needsOrganizing,
      wikiItemsPageSize,
      (input.page - 1) * wikiItemsPageSize,
    ),
    input.needsOrganizing ? null : page(true, 1, 0),
  ]);
  const items = result.error ? null : parseWikiItemRows(result.data);
  const needsOrganizingItems =
    needsOrganizing && !needsOrganizing.error
      ? parseWikiItemRows(needsOrganizing.data)
      : null;

  return {
    error:
      result.error || !items
        ? "Your Life Wiki could not load. Refresh to try again."
        : null,
    items: items ?? [],
    needsOrganizingCount: input.needsOrganizing
      ? (items?.[0]?.totalCount ?? 0)
      : (needsOrganizingItems?.[0]?.totalCount ?? 0),
  };
}

export function parseWikiItemRows(value: unknown): WikiItemSummary[] | null {
  if (!Array.isArray(value)) return null;
  const items: WikiItemSummary[] = [];
  for (const candidate of value) {
    if (!isWikiItemRow(candidate)) return null;
    items.push({
      excerpt: candidate.excerpt,
      id: candidate.canonical_item_id,
      itemKind: candidate.item_kind,
      itemSubtype: candidate.item_subtype,
      occurredEnd: candidate.occurred_end,
      occurredStart: candidate.occurred_start,
      recordId: candidate.item_id,
      recordSource: candidate.record_source,
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
    row.record_source === "entry" &&
    isWikiItemKind(row.item_kind) &&
    typeof row.item_subtype === "string" &&
    typeof row.title === "string" &&
    typeof row.excerpt === "string" &&
    (row.occurred_start === null || typeof row.occurred_start === "string") &&
    (row.occurred_end === null || typeof row.occurred_end === "string") &&
    typeof row.updated_at === "string" &&
    Number.isFinite(Number(row.total_count))
  );
}
