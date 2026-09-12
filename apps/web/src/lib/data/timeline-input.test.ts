import { describe, expect, it } from "vitest";
import {
  localDateToISOString,
  localDateValue,
  parseTimelineEntryInput,
  type TimelineEntryInput,
} from "./timeline-input";

const trackId = "11111111-1111-4111-8111-111111111111";

function input(
  overrides: Partial<TimelineEntryInput> = {},
): TimelineEntryInput {
  return {
    body: "  A formative stretch.  ",
    datePrecision: "range",
    id: null,
    kind: "stage",
    occurredEnd: "2025-06-01T12:00:00.000Z",
    occurredLabel: "  Ages 18 to 22  ",
    occurredStart: "2021-08-01T12:00:00.000Z",
    occurredTimezone: "America/Los_Angeles",
    revision: null,
    title: "  College years  ",
    trackId,
    ...overrides,
  };
}

describe("parseTimelineEntryInput", () => {
  it("preserves description-only dates, partial stage ends, and raw exact instants", () => {
    for (const datePrecision of ["unknown", "age", "approximate"] as const) {
      expect(
        parseTimelineEntryInput(
          input({
            datePrecision,
            occurredStart: null,
            occurredEnd: null,
            occurredLabel: datePrecision === "unknown" ? null : "Ages 12 to 25",
          }),
        ),
      ).toMatchObject({
        success: true,
        data: { occurredStart: null, occurredEnd: null },
      });
    }
    expect(
      parseTimelineEntryInput(input({ datePrecision: "year" })).success,
    ).toBe(true);
    const raw = "2026-11-01T09:30:00.123456Z";
    expect(
      parseTimelineEntryInput(
        input({
          datePrecision: "exact",
          occurredStart: raw,
          occurredEnd: null,
        }),
      ),
    ).toMatchObject({ success: true, data: { occurredStart: raw } });
    expect(
      parseTimelineEntryInput(
        input({
          datePrecision: "age",
          occurredStart: null,
          occurredEnd: null,
          occurredLabel: null,
        }),
      ).success,
    ).toBe(false);
    expect(
      parseTimelineEntryInput(input({ datePrecision: "unknown" })).success,
    ).toBe(false);
  });
  it("normalizes a valid stage", () => {
    const parsed = parseTimelineEntryInput(input());

    expect(parsed).toMatchObject({
      data: {
        body: "A formative stretch.",
        occurredLabel: "Ages 18 to 22",
        title: "College years",
      },
      success: true,
    });
  });

  it("accepts an event without an end date", () => {
    expect(
      parseTimelineEntryInput(
        input({
          datePrecision: "day",
          kind: "event",
          occurredEnd: null,
          title: "First time skiing",
        }),
      ).success,
    ).toBe(true);
  });

  it("requires a title and valid track", () => {
    expect(parseTimelineEntryInput(input({ title: " " }))).toMatchObject({
      success: false,
    });
    expect(
      parseTimelineEntryInput(input({ trackId: "not-a-track" })),
    ).toMatchObject({ success: false });
  });

  it("rejects an event end and a reversed stage", () => {
    expect(
      parseTimelineEntryInput(
        input({ kind: "event", occurredEnd: "2025-06-01T12:00:00.000Z" }),
      ),
    ).toMatchObject({ success: false });
    expect(
      parseTimelineEntryInput(
        input({ occurredStart: "2026-01-01T12:00:00.000Z" }),
      ),
    ).toMatchObject({ success: false });
  });

  it("rejects malformed dates and time zones", () => {
    expect(
      parseTimelineEntryInput(input({ occurredStart: "not-a-date" })),
    ).toMatchObject({ success: false });
    expect(
      parseTimelineEntryInput(input({ occurredTimezone: " " })),
    ).toMatchObject({ success: false });
  });

  it("requires an id and positive revision together", () => {
    expect(parseTimelineEntryInput(input({ revision: 2 }))).toMatchObject({
      success: false,
    });
    expect(
      parseTimelineEntryInput(
        input({ id: "22222222-2222-4222-8222-222222222222", revision: 2 }),
      ).success,
    ).toBe(true);
  });
});

describe("Timeline date conversion", () => {
  it("anchors local date input at noon before converting it", () => {
    const result = localDateToISOString("2026-07-03", "America/Los_Angeles");

    expect(result).toBe("2026-07-03T19:00:00.000Z");
    expect(localDateValue(result ?? "", "America/Los_Angeles")).toBe(
      "2026-07-03",
    );
  });

  it("rejects impossible calendar dates", () => {
    expect(localDateToISOString("2026-02-30")).toBeNull();
    expect(localDateToISOString("07/03/2026")).toBeNull();
  });

  it("falls back safely for an invalid preserved time zone", () => {
    expect(localDateValue("2026-07-03T12:00:00.000Z", "not-a-time-zone")).toBe(
      "2026-07-03",
    );
  });
});
