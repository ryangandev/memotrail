import "server-only";
import {
  entryDisplayTitle,
  occurrenceLabel,
  occurrencePrecisions,
  storedOccurrence,
  type OccurrencePrecision,
} from "./occurrence";
import {
  validTagName,
  type TagEntryPreview,
  type TagEntryPreviewResult,
} from "./organization";

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

import {
  matchPassage,
  matchedByFromReasons,
  MEANING_REASON,
} from "@/lib/search/match-presentation";
import { prepareSemanticSearch } from "@/lib/search/semantic-query";
import {
  KEYWORD_ONLY_STATUS,
  type SemanticSearchStatus,
} from "@/lib/search/semantic-state";

export type SearchEntry = {
  body: string;
  bodyRich: EntryRichText | null;
  id: string;
  itemKind: WikiItemKind;
  itemSubtype: string;
  isFirstTime: boolean;
  matchReasons: string[];
  /** The closest passage of a long Entry that matched by meaning. */
  meaningPassage: string | null;
  occurredAt: string | null;
  occurredEnd: string | null;
  datePrecision: OccurrencePrecision;
  occurredLabel: string | null;
  occurredTimezone: string | null;
  tagNames: string[];
  title: string | null;
  updatedAt: string;
};

export type SearchWorkspace = {
  entries: SearchEntry[];
  filtersError: string | null;
  loadError: string | null;
  request: SearchRequest;
  semantic: SemanticSearchStatus;
  tagOptions: string[];
  totalCount: number;
  viewer: Viewer;
};

type SearchRow = {
  body: string;
  entry_id: string;
  item_kind: WikiItemKind;
  item_subtype: string;
  is_first_time: boolean;
  match_reasons: string[] | null;
  occurred_label: string | null;
  occurred_start: string | null;
  occurred_end: string | null;
  date_precision: OccurrencePrecision;
  occurred_timezone: string | null;
  // The merged keyword-and-meaning search adds these; the keyword-only function omits them.
  semantic_char_end?: number | null;
  semantic_char_start?: number | null;
  semantic_chunk_count?: number | null;
  semantic_similarity?: number | null;
  tag_names: string[] | null;
  title: string | null;
  total_count: number | string;
  updated_at: string;
};

type NameRow = {
  name: string;
};

type ItemIdentity = {
  isFirstTime: boolean;
  itemKind: WikiItemKind;
  itemSubtype: string;
};

export async function getSearchWorkspace(
  parsed: ParsedSearchRequest,
): Promise<SearchWorkspace | null> {
  const context = await getAuthenticatedContext();

  if (!context) {
    return null;
  }

  const shouldSearch = parsed.request.hasCriteria && !parsed.error;
  const tagsRequest = context.client
    .from("tags")
    .select("name")
    .eq("owner_id", context.userId)
    .order("name")
    .returns<NameRow[]>();
  const [semantic, tags] = await Promise.all([
    shouldSearch && parsed.request.query
      ? prepareSemanticSearch(
          context.client,
          context.userId,
          parsed.request.query,
          "library",
        )
      : Promise.resolve({ arguments: null, status: KEYWORD_ONLY_STATUS }),
    tagsRequest,
  ]);
  const search = shouldSearch
    ? await context.client.rpc("search_wiki_items", {
        p_date_from: parsed.request.dateFrom,
        p_date_to: parsed.request.dateTo,
        p_item_classifications: parsed.request.itemClassifications,
        p_limit: SEARCH_PAGE_SIZE,
        p_offset: parsed.request.offset,
        // Words rank by how well they match; filters alone list by the date things happened.
        p_order: parsed.request.query ? "relevance" : "newest",
        p_query: parsed.request.query,
        p_tag_names: parsed.request.tagNames,
        ...semantic.arguments,
      })
    : { data: [] as SearchRow[], error: null };

  const parsedRows = search.error ? [] : searchRows(search.data);
  const malformedSearchResponse = shouldSearch && !search.error && !parsedRows;
  const rows = parsedRows ?? [];
  const bodyRichByEntry = await loadEntryRichTextMap(
    context,
    rows.map((row) => ({ body: row.body, id: row.entry_id })),
  );
  const filtersUnavailable = tags.error;

  return {
    entries: search.error
      ? []
      : rows.map((row) => entryFromRow(row, bodyRichByEntry.get(row.entry_id))),
    filtersError: filtersUnavailable
      ? "Tags could not load, so Library cannot filter by them right now. Search still works."
      : null,
    loadError:
      parsed.error ??
      (search.error || malformedSearchResponse
        ? "MemoTrail could not search your Entries. Try again."
        : null),
    request: parsed.request,
    semantic: semantic.status,
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

  const semantic = await prepareSemanticSearch(
    context.client,
    context.userId,
    normalizedQuery,
    "quick",
  );
  const entrySearch = await context.client.rpc("search_wiki_items", {
    p_date_from: null,
    p_date_to: null,
    p_item_classifications: [],
    p_limit: 8,
    p_offset: 0,
    p_order: "relevance",
    p_query: normalizedQuery,
    p_tag_names: [],
    ...semantic.arguments,
  });

  const entryRows = entrySearch.error ? null : searchRows(entrySearch.data);
  const items = (entryRows ?? []).map((row) => quickEntryItem(row)).slice(0, 8);

  return {
    error: entryRows
      ? null
      : "MemoTrail could not search your Entries. Try again.",
    items,
  };
}

export async function getTagEntryPreviews(
  tagName: string,
): Promise<TagEntryPreviewResult> {
  // Any name a tag can be saved with can be browsed.
  const normalizedName = validTagName(tagName);
  if (!normalizedName) {
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
  const matchedBy = matchedByFromReasons(strings(row.match_reasons));
  // A long Entry that matched only by meaning shows the passage that did.
  const passage = matchedBy === "meaning" ? rowPassage(row) : null;
  return {
    href: wikiEntryHref({ id: row.entry_id }),
    id: row.entry_id,
    label: identityLabel(identity),
    matchedBy,
    subtitle: compactText(passage ?? row.body) || "Saved Entry",
    title: rowTitle(row),
  };
}

function rowPassage(row: SearchRow) {
  return matchPassage(
    row.body,
    row.semantic_char_start ?? null,
    row.semantic_char_end ?? null,
    row.semantic_chunk_count ?? null,
  );
}

function tagEntryPreview(
  row: SearchRow,
  identity: ItemIdentity = identityFromSearchRow(row),
): TagEntryPreview {
  return {
    // An untitled Entry is already named by its date.
    date: stringValue(row.title) ? occurrenceLabel(rowOccurrence(row)) : null,
    href: wikiEntryHref({ id: row.entry_id }),
    id: row.entry_id,
    title: rowTitle(row),
    type: identityLabel(identity),
  };
}

function rowOccurrence(row: SearchRow) {
  return storedOccurrence({
    datePrecision: row.date_precision,
    occurredEnd: stringValue(row.occurred_end),
    occurredLabel: stringValue(row.occurred_label),
    occurredStart: stringValue(row.occurred_start),
    occurredTimezone: row.occurred_timezone,
  });
}

function rowTitle(row: SearchRow) {
  return entryDisplayTitle(row.title, rowOccurrence(row));
}

function compactText(value: string) {
  const compact = value.replace(/\s+/g, " ").trim();
  return compact.length > 140 ? `${compact.slice(0, 137)}...` : compact;
}

function entryFromRow(
  row: SearchRow,
  bodyRich: EntryRichText | null = null,
  identity: ItemIdentity = identityFromSearchRow(row),
): SearchEntry {
  return {
    body: row.body,
    bodyRich,
    id: row.entry_id,
    itemKind: identity.itemKind,
    itemSubtype: identity.itemSubtype,
    isFirstTime: identity.isFirstTime,
    matchReasons: strings(row.match_reasons),
    meaningPassage: strings(row.match_reasons).includes(MEANING_REASON)
      ? rowPassage(row)
      : null,
    occurredAt: stringValue(row.occurred_start),
    occurredEnd: stringValue(row.occurred_end),
    datePrecision: row.date_precision,
    occurredLabel: stringValue(row.occurred_label),
    occurredTimezone: stringValue(row.occurred_timezone),
    tagNames: strings(row.tag_names),
    title: stringValue(row.title),
    updatedAt: row.updated_at,
  };
}

function identityFromSearchRow(row: SearchRow): ItemIdentity {
  return {
    isFirstTime: row.is_first_time,
    itemKind: row.item_kind,
    itemSubtype: row.item_subtype,
  };
}

function identityLabel(identity: ItemIdentity) {
  return wikiItemIdentityLabel(identity.itemSubtype, identity.isFirstTime);
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
    typeof value.is_first_time === "boolean" &&
    typeof value.updated_at === "string" &&
    nullableString(value.title) &&
    nullableString(value.occurred_label) &&
    nullableString(value.occurred_start) &&
    nullableString(value.occurred_end) &&
    occurrencePrecisions.includes(
      value.date_precision as OccurrencePrecision,
    ) &&
    nullableString(value.occurred_timezone) &&
    nullableStringArray(value.match_reasons) &&
    nullableStringArray(value.tag_names) &&
    optionalNullableNumber(value.semantic_char_start) &&
    optionalNullableNumber(value.semantic_char_end) &&
    optionalNullableNumber(value.semantic_chunk_count) &&
    optionalNullableNumber(value.semantic_similarity) &&
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

function optionalNullableNumber(value: unknown) {
  return value === undefined || value === null || typeof value === "number";
}

function nullableStringArray(value: unknown) {
  return (
    value === null ||
    (Array.isArray(value) && value.every((item) => typeof item === "string"))
  );
}
