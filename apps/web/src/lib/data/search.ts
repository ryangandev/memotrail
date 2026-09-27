import "server-only";
import {
  occurrenceLabel,
  occurrencePrecisions,
  validTimezone,
  type OccurrencePrecision,
} from "./occurrence";
import type { TagEntryPreview, TagEntryPreviewResult } from "./organization";

import {
  getAuthenticatedContext,
  loadEntryRichTextMap,
  type Viewer,
} from "@/lib/data/inbox";
import type { EntryRichText } from "@/lib/data/rich-text";
import {
  SEARCH_PAGE_SIZE,
  type ParsedSearchRequest,
  type QuickSearchItem,
  type QuickSearchResult,
  type SearchRequest,
} from "@/lib/data/search-input";
import {
  isWikiItemKind,
  wikiEntryHref,
  wikiItemIdentityLabel,
  type WikiItemKind,
} from "@/lib/data/wiki-item";

export type SearchEntry = {
  body: string;
  bodyRich: EntryRichText | null;
  collectionNames: string[];
  id: string;
  inboxStatus: "organized" | "unreviewed";
  itemKind: WikiItemKind;
  itemSubtype: string;
  matchReasons: string[];
  occurredAt: string | null;
  occurredEnd: string | null;
  datePrecision: OccurrencePrecision;
  occurredLabel: string | null;
  occurredTimezone: string | null;
  recordId: string;
  recordSource: "entry" | "person";
  tagNames: string[];
  title: string | null;
  updatedAt: string;
};

export type SearchWorkspace = {
  collectionOptions: string[];
  entries: SearchEntry[];
  filtersError: string | null;
  inboxCount: number | undefined;
  loadError: string | null;
  request: SearchRequest;
  tagOptions: string[];
  totalCount: number;
  viewer: Viewer;
};

type SearchRow = {
  body: string;
  collection_names: string[] | null;
  entry_id: string;
  inbox_status: "organized" | "unreviewed";
  item_kind: WikiItemKind;
  item_subtype: string;
  match_reasons: string[] | null;
  occurred_label: string | null;
  occurred_start: string | null;
  occurred_end: string | null;
  date_precision: OccurrencePrecision;
  occurred_timezone: string | null;
  record_id: string;
  record_source: "entry" | "person";
  tag_names: string[] | null;
  title: string | null;
  total_count: number | string;
  updated_at: string;
};

type NameRow = {
  name: string;
};

type ItemIdentity = {
  itemKind: WikiItemKind;
  itemSubtype: string;
  recordId: string;
  recordSource: "entry" | "person";
};

export async function getSearchWorkspace(
  parsed: ParsedSearchRequest,
): Promise<SearchWorkspace | null> {
  const context = await getAuthenticatedContext();

  if (!context) {
    return null;
  }

  const shouldSearch = parsed.request.hasCriteria && !parsed.error;
  const searchRequest = shouldSearch
    ? context.client.rpc("search_wiki_items", {
        p_collection_names: parsed.request.collectionNames,
        p_date_from: parsed.request.dateFrom,
        p_date_to: parsed.request.dateTo,
        p_item_classifications: parsed.request.itemClassifications,
        p_limit: SEARCH_PAGE_SIZE,
        p_offset: parsed.request.offset,
        p_order: "relevance",
        p_query: parsed.request.query,
        p_tag_names: parsed.request.tagNames,
      })
    : Promise.resolve({ data: [] as SearchRow[], error: null });

  const [search, collections, tags, inbox] = await Promise.all([
    searchRequest,
    context.client
      .from("collections")
      .select("name")
      .eq("owner_id", context.userId)
      .is("archived_at", null)
      .order("name")
      .returns<NameRow[]>(),
    context.client
      .from("tags")
      .select("name")
      .eq("owner_id", context.userId)
      .order("name")
      .returns<NameRow[]>(),
    context.client
      .from("entries")
      .select("id", { count: "exact", head: true })
      .eq("owner_id", context.userId)
      .eq("inbox_status", "unreviewed")
      .is("deleted_at", null),
  ]);

  const parsedRows = search.error ? [] : searchRows(search.data);
  const malformedSearchResponse = shouldSearch && !search.error && !parsedRows;
  const rows = parsedRows ?? [];
  const bodyRichByEntry = await loadEntryRichTextMap(
    context,
    rows.map((row) => ({ body: row.body, id: row.entry_id })),
  );
  const filtersUnavailable = collections.error || tags.error;

  return {
    collectionOptions: collections.error
      ? []
      : (collections.data ?? []).map((collection) => collection.name),
    entries: search.error
      ? []
      : rows.map((row) => entryFromRow(row, bodyRichByEntry.get(row.entry_id))),
    filtersError: filtersUnavailable
      ? "Collection and tag filters are temporarily unavailable. Keyword search still works."
      : null,
    inboxCount: inbox.error ? undefined : (inbox.count ?? 0),
    loadError:
      parsed.error ??
      (search.error || malformedSearchResponse
        ? "MemoTrail could not search your Entries. Try again."
        : null),
    request: parsed.request,
    tagOptions: tags.error ? [] : (tags.data ?? []).map((tag) => tag.name),
    totalCount: search.error ? 0 : countFromRows(rows),
    viewer: context.viewer,
  };
}

export async function getQuickSearchResults(
  query: string,
): Promise<QuickSearchResult | null> {
  const context = await getAuthenticatedContext();
  if (!context) return null;

  const normalizedQuery = query.trim().slice(0, 200);
  if (!normalizedQuery) return { error: null, items: [] };

  const entrySearch = await context.client.rpc("search_wiki_items", {
    p_collection_names: [],
    p_date_from: null,
    p_date_to: null,
    p_item_classifications: [],
    p_limit: 8,
    p_offset: 0,
    p_order: "relevance",
    p_query: normalizedQuery,
    p_tag_names: [],
  });

  const entryRows = entrySearch.error ? null : searchRows(entrySearch.data);
  const items = (entryRows ?? []).map((row) => quickEntryItem(row)).slice(0, 8);

  return {
    error: entryRows
      ? null
      : "MemoTrail could not search your archive. Try again.",
    items,
  };
}

export async function getTagEntryPreviews(
  tagName: string,
): Promise<TagEntryPreviewResult> {
  const normalizedName = tagName.trim();
  if (!normalizedName || [...normalizedName].length > 60) {
    return { entries: [], error: "Choose a valid tag." };
  }

  const context = await getAuthenticatedContext();
  if (!context) {
    return {
      entries: [],
      error: "Sign in again to browse Entries using this tag.",
    };
  }

  const result = await context.client.rpc("search_wiki_items", {
    p_collection_names: [],
    p_date_from: null,
    p_date_to: null,
    p_item_classifications: [],
    p_limit: 5,
    p_offset: 0,
    p_order: "relevance",
    p_query: "",
    p_tag_names: [normalizedName],
  });
  const rows = result.error ? null : searchRows(result.data);

  if (!rows) {
    return {
      entries: [],
      error: "Could not load Entries using this tag. Try again.",
    };
  }

  return {
    entries: rows.map((row) => tagEntryPreview(row)),
    error: null,
  };
}

function quickEntryItem(
  row: SearchRow,
  identity: ItemIdentity = identityFromSearchRow(row),
): QuickSearchItem {
  const title =
    stringValue(row.title) ?? firstUsefulLine(row.body) ?? "Untitled Entry";

  return {
    href: wikiEntryHref({
      id: row.entry_id,
      inboxStatus: row.inbox_status,
      ...identity,
    }),
    id: row.entry_id,
    kind: identity.recordSource,
    label: wikiItemIdentityLabel(identity.itemKind, identity.itemSubtype),
    subtitle: compactText(row.body) || "Saved Entry",
    title,
  };
}

function tagEntryPreview(
  row: SearchRow,
  identity: ItemIdentity = identityFromSearchRow(row),
): TagEntryPreview {
  return {
    date: occurrenceLabel({
      datePrecision: row.date_precision,
      occurredAt: stringValue(row.occurred_start),
      occurredEnd: stringValue(row.occurred_end),
      occurredLabel: stringValue(row.occurred_label),
      occurredTimezone: validTimezone(row.occurred_timezone)
        ? row.occurred_timezone
        : "UTC",
    }),
    href: wikiEntryHref({
      id: row.entry_id,
      inboxStatus: row.inbox_status,
      ...identity,
    }),
    id: row.entry_id,
    title:
      stringValue(row.title) ?? firstUsefulLine(row.body) ?? "Untitled Entry",
    type: wikiItemIdentityLabel(identity.itemKind, identity.itemSubtype),
  };
}

function compactText(value: string) {
  const compact = value.replace(/\s+/g, " ").trim();
  return compact.length > 140 ? `${compact.slice(0, 137)}...` : compact;
}

function firstUsefulLine(value: string) {
  return value
    .split(/\r?\n/)
    .map((line) => line.trim())
    .find(Boolean);
}

function entryFromRow(
  row: SearchRow,
  bodyRich: EntryRichText | null = null,
  identity: ItemIdentity = identityFromSearchRow(row),
): SearchEntry {
  return {
    body: row.body,
    bodyRich,
    collectionNames: strings(row.collection_names),
    id: row.entry_id,
    inboxStatus: row.inbox_status,
    itemKind: identity.itemKind,
    itemSubtype: identity.itemSubtype,
    matchReasons: strings(row.match_reasons),
    occurredAt: stringValue(row.occurred_start),
    occurredEnd: stringValue(row.occurred_end),
    datePrecision: row.date_precision,
    occurredLabel: stringValue(row.occurred_label),
    occurredTimezone: stringValue(row.occurred_timezone),
    recordId: identity.recordId,
    recordSource: identity.recordSource,
    tagNames: strings(row.tag_names),
    title: stringValue(row.title),
    updatedAt: row.updated_at,
  };
}

function identityFromSearchRow(row: SearchRow): ItemIdentity {
  return {
    itemKind: row.item_kind,
    itemSubtype: row.item_subtype,
    recordId: row.record_id,
    recordSource: row.record_source,
  };
}

function countFromRows(rows: SearchRow[]) {
  const value = rows[0]?.total_count;
  const count = typeof value === "number" ? value : Number(value ?? 0);
  return Number.isSafeInteger(count) && count >= 0 ? count : 0;
}

function strings(value: string[] | null) {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string")
    : [];
}

function stringValue(value: string | null) {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function searchRows(value: unknown): SearchRow[] | null {
  if (!Array.isArray(value)) {
    return null;
  }

  return value.every(isSearchRow) ? value : null;
}

function isSearchRow(value: unknown): value is SearchRow {
  if (!isRecord(value)) {
    return false;
  }

  return (
    typeof value.body === "string" &&
    typeof value.entry_id === "string" &&
    isWikiItemKind(value.item_kind) &&
    typeof value.item_subtype === "string" &&
    (value.inbox_status === "organized" ||
      value.inbox_status === "unreviewed") &&
    typeof value.updated_at === "string" &&
    nullableString(value.title) &&
    nullableString(value.occurred_label) &&
    nullableString(value.occurred_start) &&
    nullableString(value.occurred_end) &&
    typeof value.record_id === "string" &&
    ["entry", "person"].includes(String(value.record_source)) &&
    occurrencePrecisions.includes(
      value.date_precision as OccurrencePrecision,
    ) &&
    nullableString(value.occurred_timezone) &&
    nullableStringArray(value.collection_names) &&
    nullableStringArray(value.match_reasons) &&
    nullableStringArray(value.tag_names) &&
    (typeof value.total_count === "number" ||
      typeof value.total_count === "string")
  );
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function nullableString(value: unknown) {
  return value === null || typeof value === "string";
}

function nullableStringArray(value: unknown) {
  return (
    value === null ||
    (Array.isArray(value) && value.every((item) => typeof item === "string"))
  );
}
