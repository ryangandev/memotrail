import { describe, expect, it } from "vitest";
import { parseInboxReviewInput } from "./inbox-review";
import { createEntryRichText, plainTextDocument } from "./rich-text";

const validInput = {
  body: "Small forces trigger bone remodeling.",
  collectionNames: ["Learning", "Health"],
  entryType: "standard",
  id: "f4d2df16-a506-4be6-a63e-b7b18afe3468",
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

  it("requires a title for a First Time", () => {
    expect(
      parseInboxReviewInput({
        ...validInput,
        entryType: "first_time",
        title: " ",
      }),
    ).toEqual({
      message: "Add a title before marking an Entry as a First Time.",
      success: false,
    });
  });

  it("rejects unsupported types and invalid revisions", () => {
    expect(
      parseInboxReviewInput({ ...validInput, entryType: "vehicle" }).success,
    ).toBe(false);
    expect(parseInboxReviewInput({ ...validInput, revision: 0 }).success).toBe(
      false,
    );
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
