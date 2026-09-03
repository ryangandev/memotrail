import { describe, expect, it } from "vitest";
import {
  greetingInTimezone,
  homeTimezoneCookieName,
  localDateInTimezone,
  normalizeHomeTimezone,
} from "./home-input";

describe("Home local context", () => {
  it("uses a stable client timezone cookie name", () => {
    expect(homeTimezoneCookieName).toBe("memotrail_timezone");
  });

  it("accepts a trimmed IANA timezone", () => {
    expect(normalizeHomeTimezone(" America/Los_Angeles ")).toBe(
      "America/Los_Angeles",
    );
  });

  it("falls back to UTC for absent or invalid timezones", () => {
    expect(normalizeHomeTimezone(undefined)).toBe("UTC");
    expect(normalizeHomeTimezone("Not/AZone")).toBe("UTC");
    expect(normalizeHomeTimezone("x".repeat(101))).toBe("UTC");
  });

  it("derives different local dates across a UTC boundary", () => {
    const date = new Date("2026-09-03T01:00:00Z");

    expect(localDateInTimezone(date, "America/Los_Angeles")).toBe("2026-09-02");
    expect(localDateInTimezone(date, "Asia/Tokyo")).toBe("2026-09-03");
  });

  it("uses the normalized timezone for greetings", () => {
    const date = new Date("2026-09-03T15:00:00Z");

    expect(greetingInTimezone(date, "America/Los_Angeles")).toBe(
      "Good morning",
    );
    expect(greetingInTimezone(date, "Europe/London")).toBe("Good afternoon");
    expect(
      greetingInTimezone(new Date("2026-09-03T10:00:00Z"), "Asia/Tokyo"),
    ).toBe("Good evening");
  });
});
