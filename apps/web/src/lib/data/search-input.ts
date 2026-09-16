export const SEARCH_PAGE_SIZE = 25;
export const SEARCH_QUERY_LIMIT = 200;

export type RawSearchParams = Record<string, string | string[] | undefined>;

export type SearchRequest = {
  collectionNames: string[];
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
  kind: "entry" | "person" | "place";
  label: string;
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

  return result.items.every(
    (item) =>
      item &&
      typeof item.id === "string" &&
      ["entry", "person", "place"].includes(item.kind) &&
      typeof item.href === "string" &&
      item.href.startsWith("/") &&
      !item.href.startsWith("//") &&
      typeof item.label === "string" &&
      typeof item.subtitle === "string" &&
      typeof item.title === "string",
  )
    ? result
    : null;
}

export function parseSearchRequest(
  parameters: RawSearchParams,
): ParsedSearchRequest {
  const query = firstValue(parameters.q).trim();
  const itemClassifications = normalizedValues(parameters.type);
  const collectionNames = normalizedValues(parameters.collection);
  const tagNames = normalizedValues(parameters.tag);
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
  } else if (!validNames(collectionNames, 20, 80)) {
    error = "Choose up to 20 valid Collections.";
  } else if (!validNames(tagNames, 50, 60)) {
    error = "Choose up to 50 valid tags.";
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
      collectionNames,
      dateFrom,
      dateTo,
      itemClassifications,
      hasCriteria:
        query.length > 0 ||
        itemClassifications.length > 0 ||
        collectionNames.length > 0 ||
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

export function searchPageHref(request: SearchRequest, page: number) {
  const parameters = new URLSearchParams();

  if (request.query) {
    parameters.set("q", request.query);
  }

  for (const classification of request.itemClassifications) {
    parameters.append("type", classification);
  }

  for (const collectionName of request.collectionNames) {
    parameters.append("collection", collectionName);
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
  return queryString ? `/search?${queryString}` : "/search";
}

function firstValue(value: string | string[] | undefined) {
  if (Array.isArray(value)) {
    return value[0] ?? "";
  }

  return value ?? "";
}

function normalizedValues(value: string | string[] | undefined) {
  const values = Array.isArray(value) ? value : value ? [value] : [];
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
