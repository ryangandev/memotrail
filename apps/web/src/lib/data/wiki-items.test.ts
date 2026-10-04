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
  item_kind: "entry",
  item_subtype: "entry",
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
        itemKind: "entry",
        itemSubtype: "entry",
        recordId: item.item_id,
        recordSource: "entry",
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

  it("counts the Entries that still need organizing beside the full list", async () => {
    const rpc = vi.fn((_name: string, parameters: Record<string, unknown>) =>
      Promise.resolve({
        data: parameters.p_needs_organizing
          ? [{ ...item, total_count: 2 }]
          : [item],
        error: null,
      }),
    );
    vi.mocked(getAuthenticatedContext).mockResolvedValue({
      client: { rpc },
    } as never);

    const all = await getWikiItemsWorkspace({
      itemKind: null,
      needsOrganizing: false,
      page: 2,
      query: "",
    });
    expect(all).toMatchObject({ error: null, needsOrganizingCount: 2 });
    expect(rpc).toHaveBeenCalledWith(
      "wiki_items_workspace",
      expect.objectContaining({
        p_limit: 12,
        p_needs_organizing: false,
        p_offset: 12,
      }),
    );
    expect(rpc).toHaveBeenCalledWith(
      "wiki_items_workspace",
      expect.objectContaining({ p_limit: 1, p_needs_organizing: true }),
    );

    rpc.mockClear();
    const needsOrganizing = await getWikiItemsWorkspace({
      itemKind: null,
      needsOrganizing: true,
      page: 1,
      query: "",
    });
    expect(needsOrganizing).toMatchObject({ needsOrganizingCount: 2 });
    expect(rpc).toHaveBeenCalledTimes(1);
  });

  it("bounds pagination", () => {
    expect(wikiItemsPage("2")).toBe(2);
    expect(wikiItemsPage("0")).toBe(1);
    expect(wikiItemsPage("999999")).toBe(1);
  });
});
