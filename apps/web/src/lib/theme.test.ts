import { describe, expect, it } from "vitest";
import { explicitTheme, storedThemePreference } from "./theme";

describe("appearance preference", () => {
  it("accepts only supported values and otherwise follows the system", () => {
    expect(storedThemePreference("system")).toBe("system");
    expect(storedThemePreference("light")).toBe("light");
    expect(storedThemePreference("dark")).toBe("dark");
    expect(storedThemePreference("sepia")).toBe("system");
    expect(storedThemePreference(undefined)).toBe("system");
  });

  it("adds an explicit document theme only when requested", () => {
    expect(explicitTheme("system")).toBeUndefined();
    expect(explicitTheme("light")).toBe("light");
    expect(explicitTheme("dark")).toBe("dark");
  });
});
