import { describe, expect, it } from "vitest";
import { storedSemanticSearchPreference } from "./semantic-preference";

describe("storedSemanticSearchPreference", () => {
  it("is on by default and hidden for a database without the column", () => {
    expect(storedSemanticSearchPreference(null)).toEqual({
      available: false,
      enabled: true,
    });
    expect(storedSemanticSearchPreference({ display_name: "Sam" })).toEqual({
      available: false,
      enabled: true,
    });
  });

  it("reads the saved choice", () => {
    expect(
      storedSemanticSearchPreference({ semantic_search_enabled: false }),
    ).toEqual({ available: true, enabled: false });
    expect(
      storedSemanticSearchPreference({ semantic_search_enabled: true }),
    ).toEqual({ available: true, enabled: true });
  });
});
