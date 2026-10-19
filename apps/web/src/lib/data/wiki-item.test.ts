import { describe, expect, it } from "vitest";
import {
  wikiEntryHref,
  wikiItemIdentityLabel,
  wikiItemRecordFilters,
  wikiItemSubtypeLabel,
} from "./wiki-item";

describe("Entry identity and routing", () => {
  it("names an item by its marks", () => {
    expect(wikiItemIdentityLabel("entry")).toBe("Entry");
    expect(wikiItemIdentityLabel("entry", false)).toBe("Entry");
    expect(wikiItemIdentityLabel("entry", true)).toBe("First Time");
    expect(wikiItemIdentityLabel("chapter", false)).toBe("Chapter");
    expect(wikiItemIdentityLabel("chapter", true)).toBe("Chapter · First Time");
  });

  it("labels a subtype as a Chapter or an Entry", () => {
    expect(wikiItemSubtypeLabel("chapter")).toBe("Chapter");
    expect(wikiItemSubtypeLabel("entry")).toBe("Entry");
    expect(wikiItemSubtypeLabel("anything else")).toBe("Entry");
  });

  it("offers the three Record filters", () => {
    expect(wikiItemRecordFilters.map((option) => option.value)).toEqual([
      "entry",
      "chapter",
      "first_time",
    ]);
  });

  it("opens every item on its Item page", () => {
    expect(wikiEntryHref({ id: "1" })).toBe("/items/1");
    expect(wikiEntryHref({ id: "2" })).toBe("/items/2");
  });
});
