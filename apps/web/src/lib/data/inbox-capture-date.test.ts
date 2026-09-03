import { describe, expect, it } from "vitest";
import {
  captureDateLabel,
  localCaptureDateValue,
  parseCaptureDate,
} from "./inbox-capture-date";

describe("Inbox capture dates", () => {
  it("uses the exact capture time when no relevant date is selected", () => {
    const now = new Date("2026-09-03T08:45:12.000Z");

    expect(parseCaptureDate(null, now)).toEqual({
      occurredAt: "2026-09-03T08:45:12.000Z",
      success: true,
    });
  });

  it("converts a selected local date and time to a synchronized instant", () => {
    const localValue = "2026-07-03T09:30";
    const expected = new Date(localValue).toISOString();

    expect(parseCaptureDate(localValue, new Date())).toEqual({
      occurredAt: expected,
      success: true,
    });
  });

  it("rejects an invalid selected date", () => {
    expect(parseCaptureDate("not-a-date", new Date())).toEqual({
      message: "Choose a valid relevant date and time.",
      success: false,
    });
  });

  it("creates an editable local value and a human label", () => {
    const date = new Date(2026, 6, 3, 9, 30);
    const localValue = localCaptureDateValue(date);

    expect(localValue).toBe("2026-07-03T09:30");
    expect(captureDateLabel(localValue)).toContain("Jul 3, 2026");
  });
});
