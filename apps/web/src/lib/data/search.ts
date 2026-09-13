import "server-only";
import { occurrencePrecisions, type OccurrencePrecision } from "./occurrence";

import { getAuthenticatedContext, type Viewer } from "@/lib/data/inbox";
import {
  SEARCH_PAGE_SIZE,
  type ParsedSearchRequest,
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
): Promise<SearchWorkspace | null> {
  const context = await getAuthenticatedContext();

  if (!context) {
    return null;
  }

  const shouldSearch = parsed.request.hasCriteria && !parsed.error;
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
  const filtersUnavailable = collections.error || tags.error;

  return {
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
