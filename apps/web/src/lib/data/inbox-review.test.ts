import { describe, expect, it } from "vitest";
import { parseInboxReviewInput } from "./inbox-review";
import { createEntryRichText, plainTextDocument } from "./rich-text";

const validInput = {
  body: "Small forces trigger bone remodeling.",
  collectionNames: ["Learning", "Health"],
  id: "f4d2df16-a506-4be6-a63e-b7b18afe3468",
  location: null,
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
    const bodyRich = createEntryRichText(plainTextDocument("Different note"));

    expect(parseInboxReviewInput({ ...validInput, bodyRich })).toEqual({
      message: "This Entry's rich text is invalid.",
      success: false,
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

  it("trims and de-duplicates Collections and tags case-insensitively", () => {
    expect(
      parseInboxReviewInput({
        ...validInput,
        collectionNames: [" Learning ", "learning", "Health"],
        tagNames: [" Teeth ", "teeth", "science"],
      }),
    ).toMatchObject({
      data: {
        collectionNames: ["Learning", "Health"],
        tagNames: ["Teeth", "science"],
      },
      success: true,
    });
  });

  it("rejects blank, oversized, and excessive organization names", () => {
    expect(
      parseInboxReviewInput({ ...validInput, collectionNames: [" "] }).success,
    ).toBe(false);
    expect(
      parseInboxReviewInput({ ...validInput, tagNames: ["t".repeat(61)] })
        .success,
    ).toBe(false);
    expect(
      parseInboxReviewInput({
        ...validInput,
        collectionNames: Array.from({ length: 21 }, (_, index) => `C${index}`),
      }).success,
    ).toBe(false);
  });
});
