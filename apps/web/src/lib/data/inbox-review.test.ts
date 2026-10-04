import { describe, expect, it } from "vitest";
import { parseInboxReviewInput } from "./inbox-review";
import {
  createEntryRichText,
  plainTextDocument,
  trimEntryNote,
} from "./rich-text";

const validInput = {
  body: "Small forces trigger bone remodeling.",
  id: "f4d2df16-a506-4be6-a63e-b7b18afe3468",
  location: null,
  milestone: null,
  occurredAt: "2026-09-01T15:00:00.000Z",
  occurredTimezone: "America/Los_Angeles",
  occurredEnd: null,
  occurredLabel: null,
  datePrecision: "exact",
  revision: 1,
  tagNames: ["orthodontics"],
  title: "How aligners move teeth",
};

describe("Inbox Entry review", () => {
  it("preserves validated database microseconds instead of rounding an unchanged edit", () => {
    const raw = "2017-07-08T12:34:56.123456+00:00";
    const result = parseInboxReviewInput({ ...validInput, occurredAt: raw });
    expect(result.success).toBe(true);
    if (result.success) expect(result.data.occurredAt).toBe(raw);
  });
  it("normalizes a valid editable review", () => {
    expect(
      parseInboxReviewInput({
        ...validInput,
        body: "  Small forces trigger bone remodeling.  ",
      }),
    ).toEqual({
      data: { ...validInput, bodyRich: null },
      success: true,
    });
  });

  it("keeps validated rich text with its canonical note", () => {
    const bodyRich = createEntryRichText(
      plainTextDocument("Small forces trigger bone remodeling."),
    );

    expect(parseInboxReviewInput({ ...validInput, bodyRich })).toMatchObject({
      data: { bodyRich },
      success: true,
    });
  });

  it("rejects rich text that does not match the canonical note", () => {
    const message =
      "MemoTrail could not keep this note's formatting. Edit the note, then save again.";
    const different = createEntryRichText(plainTextDocument("Different note"));
    const untrimmed = createEntryRichText(
      plainTextDocument(`${validInput.body}\n`),
    );

    expect(
      parseInboxReviewInput({ ...validInput, bodyRich: different }),
    ).toEqual({ message, success: false });
    expect(
      parseInboxReviewInput({
        ...validInput,
        body: untrimmed!.text,
        bodyRich: untrimmed,
      }),
    ).toEqual({ message, success: false });
  });

  it("accepts a formatted note trimmed before review", () => {
    const edited = createEntryRichText(
      plainTextDocument(`  ${validInput.body}\n\n`),
    );
    const note = trimEntryNote(edited!.text, edited);

    expect(parseInboxReviewInput({ ...validInput, ...note })).toEqual({
      data: {
        ...validInput,
        bodyRich: createEntryRichText(plainTextDocument(validInput.body)),
      },
      success: true,
    });
  });

  it("ignores an old client classification and rejects invalid revisions", () => {
    expect(
      parseInboxReviewInput({
        ...validInput,
        itemKind: "event",
        itemSubtype: "first_time",
      }),
    ).toEqual({ data: { ...validInput, bodyRich: null }, success: true });
    expect(parseInboxReviewInput({ ...validInput, revision: 0 }).success).toBe(
      false,
    );
    expect(
      parseInboxReviewInput({ ...validInput, revision: undefined }).success,
    ).toBe(false);
  });

  it("adds a new Entry without photos", () => {
    expect(
      parseInboxReviewInput({ ...validInput, revision: null }),
    ).toMatchObject({ data: { revision: null }, success: true });
    expect(
      parseInboxReviewInput({
        ...validInput,
        photoLocation: {
          attachmentId: "a4d2df16-a506-4be6-a63e-b7b18afe3468",
          latitude: 39.95,
          longitude: -75.16,
        },
        revision: null,
      }).success,
    ).toBe(false);
  });

  it("marks an Entry as a Timeline milestone", () => {
    const period = {
      isFirstTime: false,
      lane: "work_study",
      shape: "period",
    } as const;
    expect(
      parseInboxReviewInput({
        ...validInput,
        datePrecision: "year",
        milestone: period,
        occurredAt: "2013-01-01T00:00:00.000Z",
        occurredEnd: "2017-01-01T00:00:00.000Z",
      }),
    ).toMatchObject({ data: { milestone: period }, success: true });
    expect(
      parseInboxReviewInput({
        ...validInput,
        milestone: { isFirstTime: true, lane: "other", shape: "moment" },
      }),
    ).toMatchObject({ data: { milestone: { isFirstTime: true } } });
    expect(
      parseInboxReviewInput({
        ...validInput,
        milestone: { isFirstTime: false, lane: "homes", shape: "period" },
      }),
    ).toEqual({
      message: "Choose how this Entry appears on Timeline.",
      success: false,
    });
    expect(
      parseInboxReviewInput({
        ...validInput,
        datePrecision: "range",
        milestone: { isFirstTime: false, lane: "other", shape: "moment" },
        occurredEnd: "2026-09-03T15:00:00.000Z",
      }),
    ).toEqual({
      message:
        "A Moment is one point in time. Remove the end date, or make it a Period.",
      success: false,
    });
  });

  it("accepts a provider Location and rejects incomplete coordinates", () => {
    const location = {
      kind: "provider",
      provider: "geoapify",
      providerLocationId: "provider-location",
      name: "10 Pine Street",
      formattedAddress: "10 Pine Street, Philadelphia, PA",
      address: "10 Pine Street",
      city: "Philadelphia",
      region: "Pennsylvania",
      postalCode: "19107",
      country: "United States",
      countryCode: "us",
      latitude: 39.95,
      longitude: -75.16,
      timezone: "America/New_York",
      resultType: "building",
      confidence: 0.98,
      matchType: "full_match",
      dataSource: "openstreetmap",
    };
    expect(parseInboxReviewInput({ ...validInput, location }).success).toBe(
      true,
    );
    expect(
      parseInboxReviewInput({
        ...validInput,
        location: { ...location, longitude: null },
      }).success,
    ).toBe(false);
  });

  it("rejects an empty Entry and invalid occurrence date", () => {
    expect(
      parseInboxReviewInput({ ...validInput, body: " ", title: null }).success,
    ).toBe(false);
    expect(
      parseInboxReviewInput({ ...validInput, occurredAt: "not a date" })
        .success,
    ).toBe(false);
  });

  it("trims and de-duplicates tags case-insensitively", () => {
    expect(
      parseInboxReviewInput({
        ...validInput,
        tagNames: [" Teeth ", "teeth", "science"],
      }),
    ).toMatchObject({
      data: {
        tagNames: ["Teeth", "science"],
      },
      success: true,
    });
  });

  it("rejects blank, oversized, and excessive organization names", () => {
    expect(
      parseInboxReviewInput({ ...validInput, tagNames: [" "] }).success,
    ).toBe(false);
    expect(
      parseInboxReviewInput({ ...validInput, tagNames: ["t".repeat(81)] })
        .success,
    ).toBe(false);
    expect(
      parseInboxReviewInput({
        ...validInput,
        tagNames: Array.from({ length: 71 }, (_, index) => `T${index}`),
      }).success,
    ).toBe(false);
  });
});
