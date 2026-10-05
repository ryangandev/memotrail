import { describe, expect, it } from "vitest";
import {
  SEARCH_PAGE_SIZE,
  parseQuickSearchResult,
  parseSearchRequest,
  librarySearchHref,
} from "./search-input";

describe("parseSearchRequest", () => {
  it("trims a query and derives the first page", () => {
    const parsed = parseSearchRequest({ q: "  skiing memories  " });

    expect(parsed).toMatchObject({
      error: null,
      request: {
        hasCriteria: true,
        offset: 0,
        page: 1,
        query: "skiing memories",
      },
    });
  });

  it("preserves filters and de-duplicates them case-insensitively", () => {
    const parsed = parseSearchRequest({
      from: "2026-01-01",
      tag: ["Snow", "snow"],
      to: "2026-12-31",
      type: ["first_time", "FIRST_TIME"],
    });

    expect(parsed.error).toBeNull();
    expect(parsed.request).toMatchObject({
      dateFrom: "2026-01-01",
      dateTo: "2026-12-31",
      itemClassifications: ["first_time"],
      hasCriteria: true,
      tagNames: ["Snow"],
    });
  });

  it("reads older Collection links as tag filters", () => {
    const parsed = parseSearchRequest({
      collection: [" Travel ", "snow"],
      tag: "Snow",
    });

    expect(parsed.error).toBeNull();
    expect(parsed.request.tagNames).toEqual(["Snow", "Travel"]);
    expect(librarySearchHref(parsed.request, 1)).toBe(
      "/library?tag=Snow&tag=Travel",
    );
  });

  it("uses a bounded page to calculate the database offset", () => {
    const parsed = parseSearchRequest({ page: "3", q: "learning" });

    expect(parsed.request.page).toBe(3);
    expect(parsed.request.offset).toBe(SEARCH_PAGE_SIZE * 2);
    expect(parseSearchRequest({ page: "402" }).request.page).toBe(1);
  });

  it("rejects an overlong query", () => {
    const parsed = parseSearchRequest({ q: "x".repeat(201) });

    expect(parsed.error).toBe("Search phrases can be up to 200 characters.");
  });

  it("rejects impossible dates and reversed ranges", () => {
    expect(parseSearchRequest({ from: "2026-02-30" }).error).toBe(
      "Choose a valid start date.",
    );
    expect(
      parseSearchRequest({ from: "2026-02-02", to: "2026-02-01" }).error,
    ).toBe("The start date must be on or before the end date.");
  });

  it("keeps an empty request idle", () => {
    const parsed = parseSearchRequest({});

    expect(parsed.error).toBeNull();
    expect(parsed.request.hasCriteria).toBe(false);
  });
});

describe("librarySearchHref", () => {
  it("preserves the full search while changing pages", () => {
    const request = parseSearchRequest({
      from: "2026-01-01",
      q: "first snow",
      tag: "skiing",
      type: "first_time",
    }).request;

    expect(librarySearchHref(request, 2)).toBe(
      "/library?q=first+snow&type=first_time&tag=skiing&from=2026-01-01&page=2",
    );
  });
});

describe("parseQuickSearchResult", () => {
  it("accepts bounded owner-safe result links", () => {
    expect(
      parseQuickSearchResult({
        error: null,
        items: [
          {
            href: "/items/123",
            id: "123",
            label: "Entry",
            subtitle: "A saved note",
            title: "Remember this",
          },
        ],
      }),
    ).not.toBeNull();
  });

  it("rejects malformed and external result links", () => {
    expect(
      parseQuickSearchResult({
        error: null,
        items: [
          {
            href: "https://example.com",
            id: "123",
            label: "Entry",
            subtitle: "A saved note",
            title: "Remember this",
          },
        ],
      }),
    ).toBeNull();
    expect(
      parseQuickSearchResult({ error: null, items: Array(9).fill({}) }),
    ).toBeNull();
  });
});
