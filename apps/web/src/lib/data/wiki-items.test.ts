import { describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));
vi.mock("./inbox", () => ({ getAuthenticatedContext: vi.fn() }));

import { parseWikiItemRows, wikiItemHref, wikiItemsPage } from "./wiki-items";

const item = {
  excerpt: "A reflection",
  inbox_status: "organized",
  item_id: "40000000-0000-4000-8000-000000000001",
  item_kind: "writing",
  item_subtype: "reflection",
  occurred_end: null,
  occurred_start: null,
  record_source: "entry",
  title: "Morning pages",
  total_count: 3,
  updated_at: "2026-09-16T00:00:00Z",
};

describe("Life Wiki workspace data", () => {
  it("parses a unified item row", () => {
    expect(parseWikiItemRows([item])).toEqual([
      expect.objectContaining({
        itemKind: "writing",
        itemSubtype: "reflection",
        recordSource: "entry",
        totalCount: 3,
      }),
    ]);
  });

  it("rejects malformed semantic identity", () => {
    expect(parseWikiItemRows([{ ...item, item_kind: "entry" }])).toBeNull();
    expect(parseWikiItemRows([{ ...item, total_count: "many" }])).toBeNull();
  });

  it("routes specialized and registry Entities to their editors", () => {
    const parsed = parseWikiItemRows([item])![0];
    expect(wikiItemHref(parsed)).toBe(`/history?entry=${parsed.id}`);
    expect(
      wikiItemHref({
        ...parsed,
        itemKind: "entity",
        itemSubtype: "vehicle",
      }),
    ).toBe(`/vehicles?entry=${parsed.id}`);
    expect(
      wikiItemHref({
        ...parsed,
        itemKind: "entity",
        itemSubtype: "person",
        recordSource: "person",
      }),
    ).toBe(`/people?person=${parsed.id}`);
  });

  it("bounds pagination", () => {
    expect(wikiItemsPage("2")).toBe(2);
    expect(wikiItemsPage("0")).toBe(1);
    expect(wikiItemsPage("999999")).toBe(1);
  });
});
