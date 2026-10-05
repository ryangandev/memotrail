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
    expect(
      wikiItemIdentityLabel("entry", "entry", {
        isFirstTime: true,
        shape: "moment",
      }),
    ).toBe("First Time");
    expect(
      wikiItemIdentityLabel("entry", "entry", {
        isFirstTime: false,
        shape: "moment",
      }),
    ).toBe("Moment");
    expect(
      wikiItemIdentityLabel("entry", "entry", {
        isFirstTime: false,
        shape: "period",
      }),
    ).toBe("Period");
    expect(wikiItemSubtypeLabel("entity", "vehicle")).toBe("Vehicle");
  });

  it("routes Entries, milestones included, to their detail and focused records to their views", () => {
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
  });
});
