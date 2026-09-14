import { describe, expect, it } from "vitest";
import { timezoneOffsetLabel, timezoneOptionLabel } from "@/lib/data/timezones";

describe("timezone option labels", () => {
  it("shows whole-hour and fractional UTC offsets", () => {
    expect(timezoneOffsetLabel("UTC", "2026-09-14")).toBe("UTC+00:00");
    expect(timezoneOffsetLabel("America/Los_Angeles", "2026-09-14")).toBe(
      "UTC-07:00",
    );
    expect(timezoneOffsetLabel("Asia/Kathmandu", "2026-09-14")).toBe(
      "UTC+05:45",
    );
  });

  it("uses the relevant date when daylight saving changes the offset", () => {
    expect(timezoneOffsetLabel("America/Los_Angeles", "2026-01-14")).toBe(
      "UTC-08:00",
    );
    expect(timezoneOptionLabel("America/Los_Angeles", "2026-09-14")).toBe(
      "(UTC-07:00) Los Angeles - America",
    );
  });
});
