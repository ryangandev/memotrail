import { tagNameCountLimit, tagNameLengthLimit } from "./organization";
import type { QuickMatchedBy } from "@/lib/search/match-presentation";

export const SEARCH_PAGE_SIZE = 25;
export const SEARCH_QUERY_LIMIT = 200;

export type RawSearchParams = Record<string, string | string[] | undefined>;

export type SearchRequest = {
  dateFrom: string | null;
  dateTo: string | null;
  itemClassifications: string[];
  hasCriteria: boolean;
  offset: number;
  page: number;
  query: string;
  tagNames: string[];
};

export type ParsedSearchRequest = {
  error: string | null;
  request: SearchRequest;
};

export type QuickSearchItem = {
  href: string;
  id: string;
  label: string;
  matchedBy: QuickMatchedBy;
  subtitle: string;
  title: string;
};

export type QuickSearchResult = {
  error: string | null;
  items: QuickSearchItem[];
};

export function parseQuickSearchResult(
  value: unknown,
): QuickSearchResult | null {
  if (!value || typeof value !== "object") return null;
  const result = value as QuickSearchResult;

  if (
    (result.error !== null && typeof result.error !== "string") ||
    !Array.isArray(result.items) ||
    result.items.length > 8
  ) {
    return null;
  }

  const valid = result.items.every(
    (item) =>
      item &&
      typeof item.id === "string" &&
      typeof item.href === "string" &&
      item.href.startsWith("/") &&
      !item.href.startsWith("//") &&
      typeof item.label === "string" &&
      typeof item.subtitle === "string" &&
      typeof item.title === "string" &&
      // An older server omits how a result matched, which means its words.
      (item.matchedBy === undefined || quickMatchedBy.includes(item.matchedBy)),
  );
  if (!valid) return null;

  return {
    ...result,
    items: result.items.map((item) => ({
      ...item,
      matchedBy: item.matchedBy ?? "words",
    })),
  };
}

const quickMatchedBy: readonly string[] = ["both", "meaning", "words"];

export function parseSearchRequest(
  parameters: RawSearchParams,
): ParsedSearchRequest {
  const query = firstValue(parameters.q).trim();
  const itemClassifications = currentClassifications(
    normalizedValues(parameters.type),
  );
  // Collections became tags with the same names, so older links still filter.
  const tagNames = normalizedValues([
    ...listValues(parameters.tag),
    ...listValues(parameters.collection),
  ]);
  const dateFromValue = firstValue(parameters.from).trim();
  const dateToValue = firstValue(parameters.to).trim();
  const dateFrom = dateFromValue || null;
  const dateTo = dateToValue || null;
  const page = parsedPage(firstValue(parameters.page));
  let error: string | null = null;

  if (query.length > SEARCH_QUERY_LIMIT) {
    error = `Search phrases can be up to ${SEARCH_QUERY_LIMIT} characters.`;
  } else if (!validNames(itemClassifications, 20, 80)) {
    error = "Choose up to 20 valid Kinds or types.";
  } else if (!validNames(tagNames, tagNameCountLimit, tagNameLengthLimit)) {
    error = `Choose up to ${tagNameCountLimit} valid tags.`;
  } else if (dateFrom && !isISODate(dateFrom)) {
    error = "Choose a valid start date.";
  } else if (dateTo && !isISODate(dateTo)) {
    error = "Choose a valid end date.";
  } else if (dateFrom && dateTo && dateFrom > dateTo) {
    error = "The start date must be on or before the end date.";
  }

  return {
    error,
    request: {
      dateFrom,
      dateTo,
      itemClassifications,
      hasCriteria:
        query.length > 0 ||
        itemClassifications.length > 0 ||
        tagNames.length > 0 ||
        Boolean(dateFrom) ||
        Boolean(dateTo),
      offset: (page - 1) * SEARCH_PAGE_SIZE,
      page,
      query,
      tagNames,
    },
  };
}

export function librarySearchHref(request: SearchRequest, page: number) {
  const parameters = new URLSearchParams();

  if (request.query) {
    parameters.set("q", request.query);
  }

  for (const classification of request.itemClassifications) {
    parameters.append("type", classification);
  }

  for (const tagName of request.tagNames) {
    parameters.append("tag", tagName);
  }

  if (request.dateFrom) {
    parameters.set("from", request.dateFrom);
  }

  if (request.dateTo) {
    parameters.set("to", request.dateTo);
  }

  if (page > 1) {
    parameters.set("page", String(page));
  }

  const queryString = parameters.toString();
  return queryString ? `/library?${queryString}` : "/library";
}

function firstValue(value: string | string[] | undefined) {
  if (Array.isArray(value)) {
    return value[0] ?? "";
  }

  return value ?? "";
}

function listValues(value: string | string[] | undefined) {
  return Array.isArray(value) ? value : value ? [value] : [];
}

function normalizedValues(value: string | string[] | undefined) {
  const values = listValues(value);
  const seen = new Set<string>();
  const normalized: string[] = [];

  for (const candidate of values) {
    const trimmed = candidate.trim();
    const key = trimmed.toLocaleLowerCase();

    if (!trimmed || seen.has(key)) {
      continue;
    }

    seen.add(key);
    normalized.push(trimmed);
  }

  return normalized;
}

// Homes, Vehicles, and Timeline milestones became Chapters and First Times, so links that filter
// by the older types keep working. A milestone was either, so it stands for both.
const olderClassifications: Record<string, readonly string[]> = {
  entity: ["chapter"],
  home: ["chapter"],
  milestone: ["chapter", "first_time"],
  vehicle: ["chapter"],
};

function currentClassifications(values: string[]) {
  const seen = new Set<string>();
  const current: string[] = [];

  for (const value of values) {
    for (const mapped of olderClassifications[value.toLocaleLowerCase()] ?? [
      value,
    ]) {
      const key = mapped.toLocaleLowerCase();
      if (seen.has(key)) continue;
      seen.add(key);
      current.push(mapped);
    }
  }

  return current;
}

function validNames(
  values: string[],
  maximumCount: number,
  maximumLength: number,
) {
  return (
    values.length <= maximumCount &&
    values.every((value) => value.length <= maximumLength)
  );
}

function isISODate(value: string) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    return false;
  }

  const date = new Date(`${value}T00:00:00.000Z`);
  return (
    !Number.isNaN(date.valueOf()) && date.toISOString().slice(0, 10) === value
  );
}

function parsedPage(value: string) {
  if (!/^\d+$/.test(value)) {
    return 1;
  }

  const page = Number(value);
  return Number.isSafeInteger(page) && page >= 1 && page <= 401 ? page : 1;
}
