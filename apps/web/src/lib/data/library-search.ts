import { isFirstTimeUuid } from "./first-time-input";
import { searchPageHref, type SearchRequest } from "./search-input";

export const librarySearchPageSize = 20;
export type LibrarySearchItem = {
  id: string;
  kind: "person" | "place";
  name: string;
  excerpt: string;
  match_reasons: string[];
};
export type LibrarySearchResult = {
  items: LibrarySearchItem[];
  total_count: number;
};

export function hasLibrarySearchScope(request: SearchRequest) {
  return libraryKindsForSearch(request).length > 0;
}

export function libraryKindsForSearch(
  request: SearchRequest,
): ("person" | "place")[] {
  if (
    !request.query.trim() ||
    request.collectionNames.length > 0 ||
    request.tagNames.length > 0 ||
    request.dateFrom ||
    request.dateTo
  ) {
    return [];
  }

  if (request.itemClassifications.length === 0) {
    return ["person", "place"];
  }

  const classifications = new Set(request.itemClassifications);
  if (classifications.has("entity")) {
    return ["person", "place"];
  }

  const kinds: ("person" | "place")[] = [];
  if (classifications.has("person")) kinds.push("person");
  if (classifications.has("place")) kinds.push("place");
  return kinds;
}

export function hasUnappliedLibraryFilters(request: SearchRequest) {
  return (
    Boolean(request.query.trim()) &&
    libraryKindsForSearch(request).length === 0 &&
    (request.collectionNames.length > 0 ||
      request.tagNames.length > 0 ||
      Boolean(request.dateFrom) ||
      Boolean(request.dateTo) ||
      request.itemClassifications.length > 0)
  );
}
export function librarySearchPage(value: string | string[] | undefined) {
  const raw = Array.isArray(value) ? value[0] : value;
  if (raw !== undefined && !/^\d+$/.test(raw)) return 1;
  const page = Number(raw ?? 1);
  return Number.isSafeInteger(page) && page >= 1 && page <= 501 ? page : 1;
}
export function librarySearchHref(request: SearchRequest, page: number) {
  const url = new URL(
    searchPageHref(request, request.page),
    "http://localhost",
  );
  if (page > 1) url.searchParams.set("libraryPage", String(page));
  return url.pathname + url.search;
}
export function libraryItemHref(item: Pick<LibrarySearchItem, "id" | "kind">) {
  return item.kind === "place"
    ? `/places?place=${item.id}`
    : `/people?person=${item.id}`;
}
export function parseLibrarySearch(value: unknown): LibrarySearchResult | null {
  if (!value || typeof value !== "object") return null;
  const result = value as LibrarySearchResult;
  if (
    !Number.isSafeInteger(result.total_count) ||
    result.total_count < 0 ||
    !Array.isArray(result.items) ||
    result.items.length > 50
  )
    return null;
  if (
    !result.items.every(
      (item) =>
        item &&
        isFirstTimeUuid(item.id) &&
        ["person", "place"].includes(item.kind) &&
        typeof item.name === "string" &&
        typeof item.excerpt === "string" &&
        Array.isArray(item.match_reasons) &&
        item.match_reasons.every((reason) => typeof reason === "string"),
    )
  )
    return null;
  return result;
}
