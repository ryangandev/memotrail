import { describe, expect, it } from "vitest";
import {
  occurrenceDraft,
  occurrenceLabel,
  occurrenceSpanLabel,
  occurrenceDurationLabel,
  resolveOccurrenceDraft,
  validateOccurrence,
  wallTimeToISO,
  type Occurrence,
} from "./occurrence";
const original: Occurrence = {
  datePrecision: "exact",
  occurredAt: "2026-11-01T09:30:27.123Z",
  occurredEnd: null,
  occurredLabel: null,
  occurredTimezone: "America/Los_Angeles",
};
describe("precision-aware occurrence", () => {
  it("labels chapter bounds and durations only as precisely as recorded", () => {
    const chapter: Occurrence = {
      ...original,
      occurredAt: "2020-03-12T12:00:00Z",
      occurredEnd: "2026-09-03T12:00:00Z",
      datePrecision: "month",
    };
    expect(occurrenceSpanLabel(chapter)).toBe("Mar 2020 - Sep 2026");
    expect(occurrenceDurationLabel(chapter)).toBe("About 6 years 6 months");
    expect(occurrenceSpanLabel({ ...chapter, datePrecision: "year" })).toBe(
      "2020 - 2026",
    );
    expect(occurrenceDurationLabel({ ...chapter, datePrecision: "year" })).toBe(
      "About 6 years",
    );
    expect(
      occurrenceDurationLabel({ ...chapter, datePrecision: "range" }),
    ).toBe("6 years 5 months");
    expect(
      occurrenceDurationLabel({
        ...chapter,
        datePrecision: "unknown",
        occurredAt: null,
        occurredEnd: null,
      }),
    ).toBe("Duration unavailable");
    expect(
      occurrenceSpanLabel({
        ...chapter,
        datePrecision: "age",
        occurredAt: null,
        occurredEnd: null,
        occurredLabel: "Ages 17 to 23",
      }),
    ).toBe("Ages 17 to 23");
  });
  it("preserves an unchanged instant including seconds, milliseconds and the later repeated DST hour", () => {
    const draft = occurrenceDraft(original);
    expect(draft.start).toBe("2026-11-01T01:30:27");
    expect(resolveOccurrenceDraft(draft, original)).toEqual({
      value: original,
    });
    expect(
      wallTimeToISO("2026-11-01T01:30:27", original.occurredTimezone),
    ).toBe("2026-11-01T08:30:27.000Z");
  });
  it("handles fractional time zones and rejects nonexistent wall times", () => {
    expect(wallTimeToISO("2026-09-12T12:00", "Asia/Kathmandu")).toBe(
      "2026-09-12T06:15:00.000Z",
    );
    expect(
      wallTimeToISO("2026-03-08T02:30", original.occurredTimezone),
    ).toBeNull();
    expect(wallTimeToISO("2025-02-29T12:00", "UTC")).toBeNull();
    expect(wallTimeToISO("2026-09-12T25:00", "UTC")).toBeNull();
    expect(wallTimeToISO("2026-09-12T12:00", "not-a-zone")).toBeNull();
  });
  it.each([
    ["year", "2017", "2017"],
    ["month", "2017-07", "Jul 2017"],
    ["day", "2017-07-08", "Jul 8, 2017"],
  ] as const)(
    "keeps %s precision in labels and recorded zone",
    (precision, start, label) => {
      const result = resolveOccurrenceDraft({
        precision,
        start,
        end: "",
        label: "",
        timezone: "Pacific/Auckland",
      });
      expect(result.error).toBeUndefined();
      expect(occurrenceLabel(result.value!)).toBe(label);
      expect(occurrenceDraft(result.value!).start).toBe(start);
    },
  );
  it.each(["age", "approximate"] as const)(
    "stores %s descriptions without inferring a birthday or calendar anchor",
    (precision) => {
      const result = resolveOccurrenceDraft({
        precision,
        start: "",
        end: "",
        label: "17岁，第一次去日本",
        timezone: "UTC",
      });
      expect(result.value).toMatchObject({
        occurredAt: null,
        occurredEnd: null,
        occurredLabel: "17岁，第一次去日本",
        datePrecision: precision,
      });
      expect(occurrenceLabel(result.value!)).toBe("17岁，第一次去日本");
    },
  );
  it("supports unknown and open-ended ranges, refuses reversed ranges and missing descriptions", () => {
    const unknown = {
      ...original,
      datePrecision: "unknown" as const,
      occurredAt: null,
    };
    expect(occurrenceLabel(unknown)).toBe("Date unknown");
    expect(validateOccurrence(unknown)).toBeNull();
    expect(
      validateOccurrence({ ...unknown, occurredAt: original.occurredAt }),
    ).not.toBeNull();
    const draft = {
      precision: "range" as const,
      start: "2020-01-01",
      end: "",
      label: "",
      timezone: "UTC",
    };
    expect(occurrenceLabel(resolveOccurrenceDraft(draft).value!)).toContain(
      "onward",
    );
    expect(
      resolveOccurrenceDraft({ ...draft, end: "2019-01-01" }).error,
    ).toBeDefined();
    expect(
      resolveOccurrenceDraft({ ...draft, precision: "age", start: "" }).error,
    ).toBeDefined();
    expect(
      resolveOccurrenceDraft({ ...draft, label: "x".repeat(201) }).error,
    ).toBeDefined();
  });
  it("supports an optional end date and explicit Present mode", () => {
    const draft = {
      precision: "range" as const,
      start: "2020-01-01",
      end: "",
      label: "",
      timezone: "UTC",
    };
    expect(
      resolveOccurrenceDraft({ ...draft, endMode: "present" }).value,
    ).toMatchObject({ occurredEnd: null });
    expect(
      resolveOccurrenceDraft({ ...draft, endMode: "date" }).value,
    ).toMatchObject({ occurredEnd: null });
    expect(
      resolveOccurrenceDraft({
        ...draft,
        end: "2023-01-01",
        endMode: "date",
      }).value,
    ).toMatchObject({ occurredEnd: "2023-01-01T12:00:00.000Z" });
  });
  it("supports precision-aware stage ends without relaxing ordinary Entry validation", () => {
    for (const [precision, start, end] of [
      ["year", "2017", "2023"],
      ["month", "2017-07", "2023-06"],
      ["exact", "2017-07-08T01:30:01", "2023-06-01T02:00:01"],
    ] as const) {
      const result = resolveOccurrenceDraft(
        { precision, start, end, label: "", timezone: "Asia/Kathmandu" },
        undefined,
        true,
      );
      expect(result.value?.occurredEnd).not.toBeNull();
      expect(validateOccurrence(result.value!, true)).toBeNull();
      expect(validateOccurrence(result.value!)).not.toBeNull();
      expect(
        resolveOccurrenceDraft(
          { precision, start: end, end: start, label: "", timezone: "UTC" },
          undefined,
          true,
        ).error,
      ).toBeDefined();
    }
  });
  it("rejects invalid partial dates rather than silently converting them", () => {
    for (const [precision, start] of [
      ["year", "20"],
      ["month", "2017-13"],
      ["day", "2017-02-30"],
    ] as const)
      expect(
        resolveOccurrenceDraft({
          precision,
          start,
          end: "",
          label: "",
          timezone: "UTC",
        }).error,
      ).toBeDefined();
  });
});
