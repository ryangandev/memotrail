import { describe, it, expect } from "vitest";
import { aiOriginAllowed, parseAIPreferences, formatAICost } from "./contracts";
const prefs = {
  enabled: false,
  classification: true,
  tagging: true,
  search: true,
  explore: true,
  resurfacing: false,
  photo_analysis: false,
  monthly_budget_micros: 1_000_000,
  revision: 0,
};
describe("AI controls", () => {
  it("preserves opt-outs and strips unknown fields", () => {
    expect(parseAIPreferences({ ...prefs, secret: "not persisted" })).toEqual(
      prefs,
    );
  });
  it("rejects partial or coerced preferences", () => {
    expect(parseAIPreferences({ ...prefs, enabled: "true" })).toBeNull();
    expect(parseAIPreferences({ enabled: true })).toBeNull();
  });
  it("validates budgets and revisions", () => {
    for (const n of [-1, 100_000_001, NaN, 0.5])
      expect(
        parseAIPreferences({ ...prefs, monthly_budget_micros: n }),
      ).toBeNull();
    expect(parseAIPreferences({ ...prefs, revision: -1 })).toBeNull();
  });
  it("permits an explicit zero budget", () => {
    expect(
      parseAIPreferences({ ...prefs, monthly_budget_micros: 0 }),
    ).not.toBeNull();
  });
  it("reports sub-cent costs without rounding them to zero", () => {
    expect(formatAICost(29)).toBe("$0.000029");
    expect(formatAICost(1_000_000)).toBe("$1.00");
  });
  it("requires same-origin browser requests", () => {
    expect(
      aiOriginAllowed(
        new Request("http://localhost:3100/api/ai", {
          headers: { origin: "http://127.0.0.1:3100" },
        }),
        false,
        "http://127.0.0.1:3100",
      ),
    ).toBe(true);
    expect(
      aiOriginAllowed(
        new Request("https://memo.test/api/ai", {
          headers: { origin: "https://evil.test" },
        }),
        false,
      ),
    ).toBe(false);
    expect(
      aiOriginAllowed(new Request("https://memo.test/api/ai"), false),
    ).toBe(false);
    expect(
      aiOriginAllowed(
        new Request("https://memo.test/api/ai", {
          headers: { origin: "https://memo.test" },
        }),
        false,
      ),
    ).toBe(true);
    expect(aiOriginAllowed(new Request("https://memo.test/api/ai"), true)).toBe(
      true,
    );
  });
});
