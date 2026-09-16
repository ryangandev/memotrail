import "server-only";

import { getAuthenticatedContext } from "./inbox";
import { isWikiItemKind, type WikiItemKind } from "./wiki-item";

export const wikiItemsPageSize = 36;

export type WikiItemSummary = {
  excerpt: string;
  id: string;
  inboxStatus: "organized" | "unreviewed";
  itemKind: WikiItemKind;
  itemSubtype: string;
  occurredEnd: string | null;
  occurredStart: string | null;
  recordSource: "entry" | "person" | "place";
  title: string;
  totalCount: number;
  updatedAt: string;
};

type WikiItemRow = {
  excerpt: string;
  inbox_status: "organized" | "unreviewed";
  item_id: string;
  item_kind: WikiItemKind;
  item_subtype: string;
  occurred_end: string | null;
  occurred_start: string | null;
  record_source: "entry" | "person" | "place";
  title: string;
  total_count: number | string;
  updated_at: string;
};

export async function getWikiItemsWorkspace(input: {
  itemKind: WikiItemKind | null;
  page: number;
  query: string;
}) {
  const context = await getAuthenticatedContext();
  if (!context) return null;

  const result = await context.client.rpc("wiki_items_workspace", {
    p_item_kinds: input.itemKind ? [input.itemKind] : [],
    p_item_subtypes: [],
    p_limit: wikiItemsPageSize,
    p_offset: (input.page - 1) * wikiItemsPageSize,
    p_query: input.query,
  });
  const items = result.error ? null : parseWikiItemRows(result.data);

  return {
    error:
      result.error || !items
        ? "Your Life Wiki could not load. Refresh to try again."
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
      excerpt: candidate.excerpt,
      id: candidate.item_id,
      inboxStatus: candidate.inbox_status,
      itemKind: candidate.item_kind,
      itemSubtype: candidate.item_subtype,
      occurredEnd: candidate.occurred_end,
      occurredStart: candidate.occurred_start,
      recordSource: candidate.record_source,
      title: candidate.title,
      totalCount: Number(candidate.total_count),
      updatedAt: candidate.updated_at,
    });
  }
  return items;
}

export function wikiItemHref(item: WikiItemSummary) {
  if (item.recordSource === "person") {
    return `/people?person=${item.id}`;
  }
  if (item.recordSource === "place") {
    return `/places?place=${item.id}`;
  }
  if (item.itemKind === "entity" && item.itemSubtype === "home") {
    return `/homes?entry=${item.id}`;
  }
  if (item.itemKind === "entity" && item.itemSubtype === "vehicle") {
    return `/vehicles?entry=${item.id}`;
  }
  if (item.itemKind === "goal") {
    return `/goals?entry=${item.id}`;
  }
  if (item.itemKind === "capture" && item.inboxStatus === "unreviewed") {
    return "/inbox";
  }
  return `/history?entry=${item.id}`;
}

export function wikiItemsPage(value: unknown) {
  const page = Number(value ?? 1);
  return Number.isSafeInteger(page) && page >= 1 && page <= 2_778 ? page : 1;
}

function isWikiItemRow(value: unknown): value is WikiItemRow {
  if (!value || typeof value !== "object") return false;
  const row = value as Partial<WikiItemRow>;
  return (
    typeof row.item_id === "string" &&
    ["entry", "person", "place"].includes(String(row.record_source)) &&
    isWikiItemKind(row.item_kind) &&
    typeof row.item_subtype === "string" &&
    typeof row.title === "string" &&
    typeof row.excerpt === "string" &&
    ["organized", "unreviewed"].includes(String(row.inbox_status)) &&
    (row.occurred_start === null || typeof row.occurred_start === "string") &&
    (row.occurred_end === null || typeof row.occurred_end === "string") &&
    typeof row.updated_at === "string" &&
    Number.isFinite(Number(row.total_count))
  );
}
