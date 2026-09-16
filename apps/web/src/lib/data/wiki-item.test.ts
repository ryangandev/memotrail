import { describe, expect, it } from "vitest";
import {
  initialReviewClassification,
  reviewablePresetsForKind,
  validReviewableWikiItemPreset,
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
  });
});
