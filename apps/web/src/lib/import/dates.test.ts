import { describe, expect, it } from "vitest";
import {
  dateFromFileName,
  dateFromTitle,
  exportTimeCluster,
  parseDatePropertyText,
  parseDateText,
  plausibleFileTime,
  resolveImportDate,
} from "./dates";

const resolve = (
  date: Parameters<typeof resolveImportDate>[0],
  options: Partial<Parameters<typeof resolveImportDate>[1]> = {},
) =>
  resolveImportDate(date, {
    fileModifiedAt: null,
    timezone: "America/Los_Angeles",
    undated: "leave",
    ...options,
  });

describe("parseDateText", () => {
  it("reads the English formats apps print", () => {
    expect(parseDateText("October 18, 2026")).toEqual({
      local: "2026-10-18",
      precision: "day",
    });
    expect(parseDateText("Sunday, October 18, 2026")).toEqual({
      local: "2026-10-18",
      precision: "day",
    });
    expect(parseDateText("18 Oct 2026")).toEqual({
      local: "2026-10-18",
      precision: "day",
    });
    expect(parseDateText("Oct 18, 2026 at 3:45 PM")).toEqual({
      local: "2026-10-18T15:45:00",
      precision: "exact",
    });
    expect(parseDateText("October 18, 2026 12:05 AM")).toEqual({
      local: "2026-10-18T00:05:00",
      precision: "exact",
    });
    expect(parseDateText("2026-10-18 15:45")).toEqual({
      local: "2026-10-18T15:45:00",
      precision: "exact",
    });
  });

  it("keeps the precision of month and year dates", () => {
    expect(parseDateText("October 2026")).toEqual({
      local: "2026-10",
      precision: "month",
    });
    expect(parseDateText("2019-03")).toEqual({ local: "2019-03", precision: "month" });
    expect(parseDateText("2019")).toEqual({ local: "2019", precision: "year" });
  });

  it("turns an offset into an instant", () => {
    expect(parseDateText("2026-10-18T15:45:00-07:00")).toEqual({
      instant: "2026-10-18T22:45:00.000Z",
      precision: "exact",
    });
    expect(parseDateText("October 18, 2026 3:45 PM (GMT-7)")).toEqual({
      instant: "2026-10-18T22:45:00.000Z",
      precision: "exact",
    });
  });

  it("reads a slashed date only when one reading is possible", () => {
    expect(parseDateText("10/18/2026")).toEqual({ local: "2026-10-18", precision: "day" });
    expect(parseDateText("18/10/2026")).toEqual({ local: "2026-10-18", precision: "day" });
    expect(parseDateText("05/06/2026")).toBeNull();
  });

  it("refuses what it cannot read", () => {
    expect(parseDateText("sometime last spring")).toBeNull();
    expect(parseDateText("February 30, 2026")).toBeNull();
    expect(parseDateText("")).toBeNull();
  });
});

describe("date properties, titles, and file names", () => {
  it("reads a Notion range and drops its times", () => {
    expect(parseDatePropertyText("October 18, 2026 → October 20, 2026")).toEqual({
      localEnd: "2026-10-20",
      local: "2026-10-18",
      precision: "range",
    });
    expect(parseDatePropertyText("October 18, 2026 3:00 PM → October 18, 2026 5:00 PM")).toEqual({
      local: "2026-10-18T15:00:00",
      precision: "exact",
    });
    expect(parseDatePropertyText("October 20, 2026 → October 18, 2026")).toBeNull();
  });

  it("recognizes a title that is only a date", () => {
    expect(dateFromTitle("2024-05-12")).toEqual({ local: "2024-05-12", precision: "day" });
    expect(dateFromTitle("May 12, 2024")).toEqual({ local: "2024-05-12", precision: "day" });
    expect(dateFromTitle("Trip on May 12, 2024")).toBeNull();
  });

  it("reads a date at the start of a file name", () => {
    expect(dateFromFileName("2024-05-12 Trip.md")).toEqual({ local: "2024-05-12", precision: "day" });
    expect(dateFromFileName("20240512.md")).toEqual({ local: "2024-05-12", precision: "day" });
    expect(dateFromFileName("Trip 2024-05-12.md")).toBeNull();
    expect(dateFromFileName("2024-13-45.md")).toBeNull();
  });
});

describe("resolveImportDate", () => {
  it("stores a day at noon in the chosen zone", () => {
    expect(resolve({ local: "2024-05-12", precision: "day" })).toEqual({
      datePrecision: "day",
      occurredEnd: null,
      occurredLabel: null,
      occurredStart: "2024-05-12T19:00:00.000Z",
      occurredTimezone: "America/Los_Angeles",
    });
  });

  it("reads a local time in the zone across daylight saving", () => {
    expect(resolve({ local: "2024-01-15T09:30:00", precision: "exact" }).occurredStart).toBe(
      "2024-01-15T17:30:00.000Z",
    );
    expect(resolve({ local: "2024-07-15T09:30:00", precision: "exact" }).occurredStart).toBe(
      "2024-07-15T16:30:00.000Z",
    );
  });

  it("keeps the day of a time that does not exist", () => {
    const result = resolve({ local: "2024-03-10T02:30:00", precision: "exact" });
    expect(result.datePrecision).toBe("day");
    expect(result.occurredStart).toBe("2024-03-10T19:00:00.000Z");
  });

  it("keeps an instant's own zone", () => {
    expect(
      resolve({ instant: "2024-05-12T03:00:00.000Z", precision: "exact", timezone: "Asia/Tokyo" }),
    ).toMatchObject({
      datePrecision: "exact",
      occurredStart: "2024-05-12T03:00:00.000Z",
      occurredTimezone: "Asia/Tokyo",
    });
  });

  it("keeps month, year, and range precision", () => {
    expect(resolve({ local: "2019-03", precision: "month" })).toMatchObject({
      datePrecision: "month",
    });
    expect(resolve({ local: "2019", precision: "year" })).toMatchObject({ datePrecision: "year" });
    expect(
      resolve({ local: "2024-05-01", localEnd: "2024-05-03", precision: "range" }),
    ).toMatchObject({
      datePrecision: "range",
      occurredEnd: "2024-05-03T19:00:00.000Z",
      occurredStart: "2024-05-01T19:00:00.000Z",
    });
  });

  it("never makes a date up", () => {
    expect(resolve({ precision: "unknown" })).toMatchObject({
      datePrecision: "unknown",
      occurredEnd: null,
      occurredStart: null,
    });
    expect(resolve({ label: "last spring", precision: "unknown" }).occurredLabel).toBe(
      "last spring",
    );
  });

  it("offers the file time only when asked and only when it is plausible", () => {
    const fileModifiedAt = "2023-02-03T10:00:00.000Z";
    expect(resolve({ precision: "unknown" }, { fileModifiedAt }).datePrecision).toBe("unknown");
    expect(
      resolve({ precision: "unknown" }, { fileModifiedAt, undated: "file_time" }),
    ).toMatchObject({ datePrecision: "exact", occurredStart: fileModifiedAt });
    expect(
      resolve(
        { precision: "unknown" },
        { fileModifiedAt: "1980-01-01T00:00:00.000Z", undated: "file_time" },
      ).datePrecision,
    ).toBe("unknown");
  });

  it("falls back to UTC when the zone is not valid", () => {
    expect(resolve({ local: "2024-05-12", precision: "day" }, { timezone: "Nope/Zone" })
      .occurredTimezone).toBe("UTC");
  });
});

describe("file times", () => {
  it("rejects the future and ancient times", () => {
    const now = new Date("2026-10-18T00:00:00Z");
    expect(plausibleFileTime(new Date("2027-01-01"), now)).toBe(false);
    expect(plausibleFileTime(new Date("1985-01-01"), now)).toBe(false);
    expect(plausibleFileTime(new Date("2020-01-01"), now)).toBe(true);
    expect(plausibleFileTime(null, now)).toBe(false);
  });

  it("finds the minute most files share, the moment of the export", () => {
    const export_ = new Date("2026-10-18T10:00:10Z");
    const times = [export_, export_, export_, export_, new Date("2021-04-04T08:00:00Z")];
    const cluster = exportTimeCluster(times);
    expect(cluster.has(Math.floor(export_.getTime() / 60_000))).toBe(true);
    expect(cluster.has(Math.floor(times[4].getTime() / 60_000))).toBe(false);
    expect(exportTimeCluster([new Date("2021-01-01"), new Date("2022-01-01")]).size).toBe(0);
  });
});
