import { describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));
vi.mock("./inbox", () => ({ getAuthenticatedContext: vi.fn() }));

import { getAuthenticatedContext } from "./inbox";
import {
  getWikiItemsWorkspace,
  parseWikiItemRows,
  wikiItemHref,
  wikiItemsPage,
} from "./wiki-items";

const item = {
  canonical_item_id: "40000000-0000-4000-8000-000000000001",
  excerpt: "A reflection",
  item_id: "40000000-0000-4000-8000-000000000001",
  date_precision: "day",
  item_kind: "entry",
  item_subtype: "entry",
  occurred_end: null,
  occurred_label: null,
  occurred_start: "2026-09-15T19:00:00Z",
  occurred_timezone: "America/Los_Angeles",
  title: "Morning pages",
  total_count: 3,
  updated_at: "2026-09-16T00:00:00Z",
};

describe("Life Wiki workspace data", () => {
  it("parses a unified item row", () => {
    expect(parseWikiItemRows([item])).toEqual([
      expect.objectContaining({
        datePrecision: "day",
        itemKind: "entry",
        itemSubtype: "entry",
        occurredStart: "2026-09-15T19:00:00Z",
        occurredTimezone: "America/Los_Angeles",
        totalCount: 3,
      }),
    ]);
  });

  it("rejects malformed semantic identity", () => {
    expect(
      parseWikiItemRows([{ ...item, canonical_item_id: null }]),
    ).toBeNull();
    expect(parseWikiItemRows([{ ...item, item_kind: "writing" }])).toBeNull();
    expect(parseWikiItemRows([{ ...item, total_count: "many" }])).toBeNull();
    expect(parseWikiItemRows([{ ...item, date_precision: null }])).toBeNull();
  });

  it("routes specialized and registry Entities to their editors", () => {
    const parsed = parseWikiItemRows([item])![0];
    expect(wikiItemHref(parsed)).toBe(`/items/${parsed.id}`);
    expect(
      wikiItemHref({
        ...parsed,
        itemKind: "entity",
        itemSubtype: "vehicle",
      }),
    ).toBe(`/vehicles/${parsed.id}`);
  });

  it("loads one page of the full list", async () => {
    const rpc = vi.fn(() => Promise.resolve({ data: [item], error: null }));
    vi.mocked(getAuthenticatedContext).mockResolvedValue({
      client: { rpc },
    } as never);

    expect(await getWikiItemsWorkspace(2)).toMatchObject({
      error: null,
      items: [expect.objectContaining({ title: "Morning pages" })],
    });
    expect(rpc).toHaveBeenCalledWith("wiki_items_workspace", {
      p_item_kinds: [],
      p_item_subtypes: [],
      p_limit: 12,
      p_offset: 12,
      p_query: "",
    });
  });

  it("bounds pagination", () => {
    expect(wikiItemsPage("2")).toBe(2);
    expect(wikiItemsPage("0")).toBe(1);
    expect(wikiItemsPage("999999")).toBe(1);
  });
});
