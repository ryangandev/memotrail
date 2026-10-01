import { describe, expect, it } from "vitest";
import { countLabel } from "./count-label";

describe("count labels", () => {
  it("keeps the singular only for exactly one", () => {
    expect(countLabel(1, "Entry")).toBe("1 Entry");
    expect(countLabel(0, "Entry")).toBe("0 Entries");
    expect(countLabel(3, "Entry placement")).toBe("3 Entry placements");
  });

  it("pluralizes a consonant and y as ies, and a vowel and y with s", () => {
    expect(countLabel(2, "Entry")).toBe("2 Entries");
    expect(countLabel(2, "journey")).toBe("2 journeys");
    expect(countLabel(2, "tag")).toBe("2 tags");
  });

  it("uses an explicit irregular plural", () => {
    expect(countLabel(2, "person", "people")).toBe("2 people");
    expect(countLabel(1, "person", "people")).toBe("1 person");
  });
});
