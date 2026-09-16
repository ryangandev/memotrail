import { describe, expect, it } from "vitest";
import {
  initialReviewClassification,
  reviewablePresetsForKind,
  validReviewableWikiItemPreset,
  wikiEntryHref,
  wikiItemIdentityLabel,
  wikiItemSubtypeLabel,
} from "./wiki-item";

describe("Life Wiki item classification", () => {
  it("defaults a raw Capture to a simple Writing note", () => {
    expect(
      initialReviewClassification({
        itemKind: "capture",
        itemSubtype: "quick_capture",
      }),
    ).toEqual({ itemKind: "writing", itemSubtype: "note" });
  });

  it("preserves a supported same-Kind preset", () => {
    expect(
      initialReviewClassification({
        itemKind: "event",
        itemSubtype: "memory",
      }),
    ).toEqual({ itemKind: "event", itemSubtype: "memory" });
  });

  it("keeps Entity and Goal presets out of the generic organizer", () => {
    expect(validReviewableWikiItemPreset("entity", "vehicle")).toBe(false);
    expect(validReviewableWikiItemPreset("goal", "goal")).toBe(false);
    expect(
      reviewablePresetsForKind("event").map((preset) => preset.subtype),
    ).toEqual(["memory", "first_time", "milestone", "trip"]);
  });

  it("labels specialized and fallback subtypes", () => {
    expect(wikiItemSubtypeLabel("event", "first_time")).toBe("First Time");
    expect(wikiItemSubtypeLabel("entity", "vehicle")).toBe("Vehicle");
    expect(wikiItemSubtypeLabel("writing", "field_note")).toBe("Field Note");
    expect(wikiItemIdentityLabel("event", "memory")).toBe("Event · Memory");
    expect(wikiItemIdentityLabel("goal", "goal")).toBe("Goal");
  });

  it("routes semantic items to their canonical editor", () => {
    expect(
      wikiEntryHref({
        id: "1",
        inboxStatus: "organized",
        itemKind: "entity",
        itemSubtype: "vehicle",
      }),
    ).toBe("/vehicles?entry=1");
    expect(
      wikiEntryHref({
        id: "2",
        inboxStatus: "organized",
        itemKind: "writing",
        itemSubtype: "journal",
      }),
    ).toBe("/history?entry=2");
    expect(
      wikiEntryHref({
        id: "3",
        inboxStatus: "organized",
        itemKind: "entity",
        itemSubtype: "person",
        recordId: "30",
        recordSource: "person",
      }),
    ).toBe("/people?person=30");
    expect(
      wikiEntryHref({
        id: "4",
        inboxStatus: "unreviewed",
        itemKind: "capture",
        itemSubtype: "quick_capture",
      }),
    ).toBe("/inbox?entry=4");
  });
});
