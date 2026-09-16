import { describe, expect, it } from "vitest";
import {
  hasLibrarySearchScope,
  libraryKindsForSearch,
  libraryItemHref,
  librarySearchHref,
  librarySearchPage,
  parseLibrarySearch,
} from "./library-search";
import { parseSearchRequest } from "./search-input";

const id = "94000000-0000-4000-8000-000000000001";
describe("library keyword search", () => {
  it("shares a keyword but does not reinterpret Entry-only filters", () => {
    expect(
      hasLibrarySearchScope(parseSearchRequest({ q: "学习" }).request),
    ).toBe(true);
    expect(hasLibrarySearchScope(parseSearchRequest({}).request)).toBe(false);
    for (const filters of [
      { type: "goal" },
      { collection: "Learning" },
      { tag: "health" },
      { from: "2026-01-01" },
      { to: "2026-01-31" },
    ]) {
      expect(
        hasLibrarySearchScope(
          parseSearchRequest({ q: "学习", ...filters }).request,
        ),
      ).toBe(false);
    }
  });
  it("keeps semantic Entity filters on People and Places", () => {
    expect(
      libraryKindsForSearch(
        parseSearchRequest({ q: "marina", type: "entity" }).request,
      ),
    ).toEqual(["person", "place"]);
    expect(
      libraryKindsForSearch(
        parseSearchRequest({ q: "marina", type: "person" }).request,
      ),
    ).toEqual(["person"]);
    expect(
      libraryKindsForSearch(
        parseSearchRequest({ q: "marina", type: "writing" }).request,
      ),
    ).toEqual([]);
  });
  it("preserves the Entry page and keyword when independently paging entities", () => {
    expect(
      librarySearchHref(
        parseSearchRequest({ q: "学习", page: "3" }).request,
        2,
      ),
    ).toBe("/search?q=%E5%AD%A6%E4%B9%A0&page=3&libraryPage=2");
  });
  it.each(["0", "-1", "1.5", "1e2", "502", "not-a-page"])(
    "rejects invalid library page %s",
    (value) => {
      expect(librarySearchPage(value)).toBe(1);
    },
  );
  it("accepts bounded library pages", () => {
    expect(librarySearchPage(["501", "2"])).toBe(501);
    expect(librarySearchPage(undefined)).toBe(1);
  });
  it("opens an actual kind-specific source without inventing an Entry", () => {
    expect(libraryItemHref({ id, kind: "person" })).toBe(
      `/people?person=${id}`,
    );
    expect(libraryItemHref({ id, kind: "place" })).toBe(`/places?place=${id}`);
  });
  it("validates mixed kinds and match explanations", () => {
    const item = {
      id,
      kind: "person",
      name: "学习",
      excerpt: "Notes",
      match_reasons: ["Name"],
    };
    expect(parseLibrarySearch({ items: [item], total_count: 1 })).toEqual({
      items: [item],
      total_count: 1,
    });
    expect(
      parseLibrarySearch({
        items: [{ ...item, kind: "habit" }],
        total_count: 1,
      }),
    ).toBeNull();
    expect(
      parseLibrarySearch({ items: [{ ...item, id: "bad" }], total_count: 1 }),
    ).toBeNull();
    expect(
      parseLibrarySearch({
        items: [{ ...item, match_reasons: [1] }],
        total_count: 1,
      }),
    ).toBeNull();
  });
  it.each([
    null,
    {},
    { items: [], total_count: -1 },
    { items: [], total_count: "1" },
  ])("rejects incomplete responses", (value) => {
    expect(parseLibrarySearch(value)).toBeNull();
  });
});
