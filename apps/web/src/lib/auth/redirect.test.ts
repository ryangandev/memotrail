import { describe, expect, it } from "vitest";
import { applicationOrigin, safeRelativePath } from "./redirect";

describe("safeRelativePath", () => {
  it.each([
    null,
    "",
    "inbox",
    "https://example.com",
    "//example.com",
    "/\\example.com",
  ])("falls back to the home page for %s", (value) => {
    expect(safeRelativePath(value)).toBe("/");
  });

  it("preserves a local path, query, and fragment", () => {
    expect(safeRelativePath("/inbox?filter=unread#capture")).toBe(
      "/inbox?filter=unread#capture",
    );
  });
});

describe("applicationOrigin", () => {
  const requestUrl = new URL("https://preview.example.com/auth/callback");

  it("uses the request origin outside production", () => {
    expect(
      applicationOrigin(
        requestUrl,
        "development",
        "https://memotrail.ryangan.me",
      ),
    ).toBe("https://preview.example.com");
  });

  it("uses the configured production origin and ignores its path", () => {
    expect(
      applicationOrigin(
        requestUrl,
        "production",
        " https://memotrail.ryangan.me/ignored ",
      ),
    ).toBe("https://memotrail.ryangan.me");
  });

  it.each([
    undefined,
    "",
    "not a URL",
    "javascript:alert(1)",
    "data:text/plain,MemoTrail",
  ])("falls back to the request origin for %s", (configuredUrl) => {
    expect(applicationOrigin(requestUrl, "production", configuredUrl)).toBe(
      "https://preview.example.com",
    );
  });
});
