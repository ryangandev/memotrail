import { describe, expect, it } from "vitest";
import {
  captureDateDraft,
  captureDateValue,
  resolveCaptureDate,
  todayCaptureDate,
} from "./inbox-capture-date";
import type { OccurrenceDraft } from "./occurrence";

const now = new Date("2026-09-03T20:45:12.000Z");

describe("capture dates", () => {
  it("uses the exact capture time when no day is chosen", () => {
    const captureTime = {
      value: {
        datePrecision: "exact",
        occurredAt: "2026-09-03T20:45:12.000Z",
        occurredEnd: null,
        occurredLabel: null,
        occurredTimezone: "Asia/Kathmandu",
      },
    };

    expect(resolveCaptureDate(null, now, "Asia/Kathmandu")).toEqual(
      captureTime,
    );
    // A cleared Date field falls back to the capture time too.
    expect(
      resolveCaptureDate(captureDateDraft("", "UTC"), now, "Asia/Kathmandu"),
    ).toEqual(captureTime);
  });

  it("starts a newly opened Date on today in the capture's time zone", () => {
    expect(todayCaptureDate(now, "Asia/Kathmandu")).toEqual({
      precision: "day",
      start: "2026-09-04",
      end: "",
      label: "",
      timezone: "Asia/Kathmandu",
    });
    expect(todayCaptureDate(now, "America/Los_Angeles").start).toBe(
      "2026-09-03",
    );
  });

  it("saves a chosen day at midday and a chosen time exactly", () => {
    expect(
      resolveCaptureDate(
        captureDateDraft("2017-07-08", "Asia/Kathmandu"),
        now,
        "UTC",
      ),
    ).toEqual({
      value: {
        datePrecision: "day",
        occurredAt: "2017-07-08T06:15:00.000Z",
        occurredEnd: null,
        occurredLabel: null,
        occurredTimezone: "Asia/Kathmandu",
      },
    });
    expect(
      resolveCaptureDate(
        captureDateDraft("2017-07-08T12:34", "Asia/Kathmandu"),
        now,
        "UTC",
      ).value,
    ).toMatchObject({
      datePrecision: "exact",
      occurredAt: "2017-07-08T06:49:00.000Z",
    });
  });

  it("refuses an unfinished day or a time without a day", () => {
    for (const value of ["2017-0", "T09:30"])
      expect(
        resolveCaptureDate(captureDateDraft(value, "UTC"), now, "UTC").error,
      ).toMatch(/valid calendar date/);
  });

  it("reads drafts earlier composers saved at other precisions as a day", () => {
    const draft = (patch: Partial<OccurrenceDraft>): OccurrenceDraft => ({
      precision: "day",
      start: "",
      end: "",
      label: "",
      timezone: "UTC",
      ...patch,
    });

    expect(
      captureDateValue(
        draft({ precision: "exact", start: "2017-07-08T12:34:56" }),
      ),
    ).toBe("2017-07-08T12:34");
    expect(
      captureDateValue(
        draft({ precision: "range", start: "2017-07-01", end: "2017-08-12" }),
      ),
    ).toBe("2017-07-01");
    expect(
      captureDateValue(draft({ precision: "month", start: "2017-07" })),
    ).toBe("");
    expect(
      captureDateValue(
        draft({ precision: "approximate", label: "Summer before college" }),
      ),
    ).toBe("");
    // What the field shows is what saves: no day means the capture time.
    expect(
      resolveCaptureDate(
        draft({ precision: "year", start: "2017" }),
        now,
        "UTC",
      ).value?.occurredAt,
    ).toBe(now.toISOString());
  });
});
