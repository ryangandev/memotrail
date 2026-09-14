import "server-only";
import {
  hasLibrarySearchScope,
  libraryItemHref,
  librarySearchPageSize,
  parseLibrarySearch,
  type LibrarySearchResult,
} from "./library-search";
import { occurrencePrecisions, type OccurrencePrecision } from "./occurrence";

import { getAuthenticatedContext, type Viewer } from "@/lib/data/inbox";
import {
  SEARCH_PAGE_SIZE,
  type ParsedSearchRequest,
  type QuickSearchItem,
  type QuickSearchResult,
  type SearchRequest,
} from "@/lib/data/search-input";

export type SearchEntry = {
  body: string;
  collectionNames: string[];
  entryType: string;
  id: string;
  inboxStatus: "organized" | "unreviewed";
  matchReasons: string[];
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
  library: LibrarySearchResult | null;
  libraryError: string | null;
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
  entry_type: string;
  inbox_status: "organized" | "unreviewed";
  match_reasons: string[] | null;
  occurred_label: string | null;
  occurred_start: string | null;
  occurred_end: string | null;
  date_precision: OccurrencePrecision;
  occurred_timezone: string | null;
  tag_names: string[] | null;
  title: string | null;
  total_count: number | string;
  updated_at: string;
};

type NameRow = {
  name: string;
};

export async function getSearchWorkspace(
  parsed: ParsedSearchRequest,
  libraryPage = 1,
): Promise<SearchWorkspace | null> {
  const context = await getAuthenticatedContext();

  if (!context) {
    return null;
  }

  const shouldSearch = parsed.request.hasCriteria && !parsed.error;
  const shouldSearchLibrary =
    shouldSearch && hasLibrarySearchScope(parsed.request);
  const searchRequest = shouldSearch
    ? context.client.rpc("search_entries_with_occurrence", {
        p_collection_names: parsed.request.collectionNames,
        p_date_from: parsed.request.dateFrom,
        p_date_to: parsed.request.dateTo,
        p_entry_types: parsed.request.entryTypes,
        p_limit: SEARCH_PAGE_SIZE,
        p_offset: parsed.request.offset,
        p_query: parsed.request.query,
        p_tag_names: parsed.request.tagNames,
      })
    : Promise.resolve({ data: [] as SearchRow[], error: null });

  const [search, collections, tags, inbox, librarySearch] = await Promise.all([
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
    shouldSearchLibrary
      ? context.client.rpc("search_library_entities", {
          p_query: parsed.request.query,
          p_limit: librarySearchPageSize,
          p_offset: (libraryPage - 1) * librarySearchPageSize,
          p_kinds: ["person", "place"],
        })
      : Promise.resolve({ data: null, error: null }),
  ]);

  const parsedRows = search.error ? [] : searchRows(search.data);
  const malformedSearchResponse = shouldSearch && !search.error && !parsedRows;
  const rows = parsedRows ?? [];
  const filtersUnavailable = collections.error || tags.error;

  return {
    library: parseLibrarySearch(librarySearch.data),
    libraryError:
      shouldSearchLibrary &&
      (librarySearch.error || !parseLibrarySearch(librarySearch.data))
        ? "Could not search People and Places. Refresh to try again."
        : null,
    collectionOptions: collections.error
      ? []
      : (collections.data ?? []).map((collection) => collection.name),
    entries: search.error ? [] : rows.map(entryFromRow),
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

  const [entrySearch, librarySearch] = await Promise.all([
    context.client.rpc("search_entries_with_occurrence", {
      p_collection_names: [],
      p_date_from: null,
      p_date_to: null,
      p_entry_types: [],
      p_limit: 6,
      p_offset: 0,
      p_query: normalizedQuery,
      p_tag_names: [],
    }),
    context.client.rpc("search_library_entities", {
      p_query: normalizedQuery,
      p_limit: 4,
      p_offset: 0,
      p_kinds: ["person", "place"],
    }),
  ]);

  const entryRows = entrySearch.error ? null : searchRows(entrySearch.data);
  const libraryRows = librarySearch.error
    ? null
    : parseLibrarySearch(librarySearch.data);
  const items = [
    ...(entryRows ?? []).map(quickEntryItem),
    ...(libraryRows?.items ?? []).map((item): QuickSearchItem => ({
      href: libraryItemHref(item),
      id: item.id,
      kind: item.kind,
      label: item.kind === "person" ? "Person" : "Place",
      subtitle: compactText(item.excerpt) || "Saved in your Library",
      title: item.name,
    })),
  ].slice(0, 8);
  const partialFailure = !entryRows || !libraryRows;

  return {
    error:
      partialFailure && items.length === 0
        ? "MemoTrail could not search your archive. Try again."
        : partialFailure
          ? "Some archive results are temporarily unavailable."
          : null,
    items,
  };
}

function quickEntryItem(row: SearchRow): QuickSearchItem {
  const title =
    stringValue(row.title) ?? firstUsefulLine(row.body) ?? "Untitled Entry";

  return {
    href: `/history?entry=${encodeURIComponent(row.entry_id)}`,
    id: row.entry_id,
    kind: "entry",
    label: entryTypeLabel(row.entry_type),
    subtitle: compactText(row.body) || "Saved Entry",
    title,
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

function entryTypeLabel(value: string) {
  const labels: Record<string, string> = {
    first_time: "First Time",
    goal: "Goal",
    home: "Home",
    life_stage: "Life Stage",
    standard: "Entry",
    vehicle: "Vehicle",
  };

  return labels[value] ?? "Entry";
}

function entryFromRow(row: SearchRow): SearchEntry {
  return {
    body: row.body,
    collectionNames: strings(row.collection_names),
    entryType: row.entry_type,
    id: row.entry_id,
    inboxStatus: row.inbox_status,
    matchReasons: strings(row.match_reasons),
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
    typeof value.entry_type === "string" &&
    (value.inbox_status === "organized" ||
      value.inbox_status === "unreviewed") &&
    typeof value.updated_at === "string" &&
    nullableString(value.title) &&
    nullableString(value.occurred_label) &&
    nullableString(value.occurred_start) &&
    nullableString(value.occurred_end) &&
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
