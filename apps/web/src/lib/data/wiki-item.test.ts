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

  it("routes unreviewed Entries to Inbox and focused records to their views", () => {
    expect(
      wikiEntryHref({
        id: "1",
        inboxStatus: "organized",
        itemKind: "entity",
        itemSubtype: "vehicle",
      }),
    ).toBe("/vehicles/1");
    expect(
      wikiEntryHref({
        id: "2",
        inboxStatus: "organized",
        itemKind: "entry",
        itemSubtype: "entry",
      }),
    ).toBe("/items/2");
    expect(
      wikiEntryHref({
        id: "4",
        inboxStatus: "unreviewed",
        itemKind: "entry",
        itemSubtype: "entry",
      }),
    ).toBe("/inbox?entry=4");
    expect(
      wikiEntryHref({
        id: "5",
        inboxStatus: "organized",
        itemKind: "entry",
        itemSubtype: "first_time",
      }),
    ).toBe("/first-times/5");
    expect(
      wikiEntryHref({
        id: "6",
        inboxStatus: "organized",
        itemKind: "entry",
        itemSubtype: "moment",
      }),
    ).toBe("/timeline?entry=6");
    expect(
      wikiEntryHref({
        id: "7",
        inboxStatus: "organized",
        itemKind: "entry",
        itemSubtype: "period",
      }),
    ).toBe("/timeline?entry=7");
  });
});
