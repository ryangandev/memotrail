import { describe, expect, it } from "vitest";
import {
  wikiEntryHref,
  wikiItemIdentityLabel,
  wikiItemSubtypeLabel,
} from "./wiki-item";

describe("Entry identity and routing", () => {
  it("shows a general Entry without a forced subtype label", () => {
    expect(wikiItemSubtypeLabel("entry", "entry")).toBe("Entry");
    expect(wikiItemIdentityLabel("entry", "entry")).toBe("Entry");
    expect(wikiItemIdentityLabel("entry", "first_time")).toBe("First Time");
    expect(wikiItemIdentityLabel("entry", "moment")).toBe("Moment");
    expect(wikiItemIdentityLabel("entry", "period")).toBe("Period");
    expect(wikiItemSubtypeLabel("entity", "vehicle")).toBe("Vehicle");
  });

  it("routes Entries to their detail and focused records to their views", () => {
    expect(
      wikiEntryHref({
        id: "1",
        itemKind: "entity",
        itemSubtype: "vehicle",
      }),
    ).toBe("/vehicles/1");
    expect(
      wikiEntryHref({
        id: "2",
        itemKind: "entry",
        itemSubtype: "entry",
      }),
    ).toBe("/items/2");
    expect(
      wikiEntryHref({
        id: "5",
        itemKind: "entry",
        itemSubtype: "first_time",
      }),
    ).toBe("/first-times/5");
    expect(
      wikiEntryHref({
        id: "6",
        itemKind: "entry",
        itemSubtype: "moment",
      }),
    ).toBe("/timeline?entry=6");
    expect(
      wikiEntryHref({
        id: "7",
        itemKind: "entry",
        itemSubtype: "period",
      }),
    ).toBe("/timeline?entry=7");
  });
});
