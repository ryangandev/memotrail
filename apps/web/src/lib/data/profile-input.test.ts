import { describe, expect, it } from "vitest";
import {
  parseBirthDate,
  parsePreferredName,
  parseProfileTimezone,
  storedBirthDate,
  storedProfileTimezone,
  validStoredBirthDate,
} from "./profile-input";

describe("parsePreferredName", () => {
  it("normalizes a chosen name and allows falling back to the Google name", () => {
    expect(parsePreferredName("  River  Gan  ")).toEqual({
      preferredName: "River Gan",
      success: true,
    });
    expect(parsePreferredName("   ")).toEqual({
      preferredName: null,
      success: true,
    });
  });

  it("rejects overlong and multiline values", () => {
    expect(parsePreferredName("x".repeat(81)).success).toBe(false);
    expect(parsePreferredName("River\nGan").success).toBe(false);
  });
});

describe("parseBirthDate", () => {
  it("accepts a real date or an explicit removal", () => {
    expect(parseBirthDate("1994-04-18", "2026-09-13")).toEqual({
      birthDate: "1994-04-18",
      success: true,
    });
    expect(parseBirthDate("  ", "2026-09-13")).toEqual({
      birthDate: null,
      success: true,
    });
  });

  it("rejects malformed, impossible, future, and implausibly old dates", () => {
    for (const value of [
      "1994-02-30",
      "04/18/1994",
      "2026-09-14",
      "1799-12-31",
    ]) {
      expect(parseBirthDate(value, "2026-09-13").success).toBe(false);
    }
  });
});

describe("validStoredBirthDate", () => {
  it("only accepts a complete real date", () => {
    expect(validStoredBirthDate("2000-02-29")).toBe(true);
    expect(validStoredBirthDate("2001-02-29")).toBe(false);
    expect(validStoredBirthDate(null)).toBe(false);
  });
});

describe("storedBirthDate", () => {
  it("distinguishes an unavailable rollout field from an unset date", () => {
    expect(storedBirthDate({ timezone: "UTC" })).toEqual({
      available: false,
      birthDate: null,
    });
    expect(storedBirthDate({ birth_date: null })).toEqual({
      available: true,
      birthDate: null,
    });
  });
});

describe("profile timezone", () => {
  it("accepts IANA timezones and rejects arbitrary text", () => {
    expect(parseProfileTimezone(" America/Los_Angeles ")).toEqual({
      success: true,
      timezone: "America/Los_Angeles",
    });
    expect(parseProfileTimezone("Los Angeles")).toEqual({
      message: "Choose a valid time zone.",
      success: false,
    });
  });

  it("reads the existing profile preference with a safe fallback", () => {
    expect(storedProfileTimezone({ timezone: "Asia/Shanghai" })).toEqual({
      available: true,
      timezone: "Asia/Shanghai",
    });
    expect(storedProfileTimezone({ timezone: "not-a-zone" })).toEqual({
      available: true,
      timezone: "UTC",
    });
    expect(storedProfileTimezone({ birth_date: null })).toEqual({
      available: false,
      timezone: "UTC",
    });
  });
});
