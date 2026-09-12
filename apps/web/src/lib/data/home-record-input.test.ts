import { describe, expect, it } from "vitest";
import { isHomeEntryIdentity, parseHomeEntryInput } from "./home-record-input";

const entryId = "40000000-0000-4000-8000-000000000001";
const placeId = "50000000-0000-4000-8000-000000000001";

const validInput = {
  address: " 456 Elm Street ",
  body: " A quieter home. ",
  city: " San Francisco ",
  collectionNames: [" Homes ", "homes", "Milestones"],
  country: " United States ",
  datePrecision: "range",
  id: entryId,
  latitude: 37.774929,
  longitude: -122.419418,
  moveInReason: " A new chapter. ",
  moveOutReason: " Needed more space. ",
  occurredEnd: "2026-08-31T12:00:00-07:00",
  occurredLabel: " June 2025 to August 2026 ",
  occurredStart: "2025-06-01T12:00:00-07:00",
  occurredTimezone: " America/Los_Angeles ",
  placeId,
  placeName: " California home ",
  placeNotes: " Walkable and quiet. ",
  region: " California ",
  revision: 2,
  tagNames: [" California ", "california", "favorite"],
  title: " California home ",
};

describe("parseHomeEntryInput", () => {
  it.each([
    "exact",
    "day",
    "month",
    "year",
    "range",
    "age",
    "approximate",
    "unknown",
  ])("accepts %s without inventing calendar precision", (datePrecision) => {
    const unanchored = ["age", "approximate", "unknown"].includes(
      datePrecision,
    );
    const result = parseHomeEntryInput({
      ...validInput,
      datePrecision,
      occurredStart: unanchored ? null : "2026-11-01T09:30:00.123456Z",
      occurredEnd: unanchored ? null : "2026-11-01T10:30:00.654321Z",
      occurredLabel:
        unanchored && datePrecision !== "unknown" ? "During college" : null,
      moveOutReason: null,
    });
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.occurredStart).toBe(
        unanchored ? null : "2026-11-01T09:30:00.123456Z",
      );
      expect(result.data.occurredEnd).toBe(
        unanchored ? null : "2026-11-01T10:30:00.654321Z",
      );
    }
  });
  it("normalizes a complete Home edit", () => {
    const parsed = parseHomeEntryInput(validInput);

    expect(parsed.success).toBe(true);
    if (parsed.success) {
      expect(parsed.data).toMatchObject({
        address: "456 Elm Street",
        body: "A quieter home.",
        collectionNames: ["Homes", "Milestones"],
        occurredEnd: "2026-08-31T12:00:00-07:00",
        occurredStart: "2025-06-01T12:00:00-07:00",
        occurredTimezone: "America/Los_Angeles",
        placeName: "California home",
        tagNames: ["California", "favorite"],
        title: "California home",
      });
    }
  });

  it("accepts a new open-ended Home without coordinates", () => {
    expect(
      parseHomeEntryInput({
        ...validInput,
        id: null,
        latitude: null,
        longitude: null,
        moveOutReason: null,
        occurredEnd: null,
        placeId: null,
        revision: null,
      }),
    ).toMatchObject({ success: true });
  });

  it("requires a Home and Place name", () => {
    expect(parseHomeEntryInput({ ...validInput, title: " " })).toMatchObject({
      success: false,
    });
    expect(
      parseHomeEntryInput({ ...validInput, placeName: " " }),
    ).toMatchObject({ success: false });
  });

  it("requires the best-known move-in date and timezone", () => {
    expect(
      parseHomeEntryInput({ ...validInput, occurredStart: "" }),
    ).toMatchObject({ success: false });
    expect(
      parseHomeEntryInput({ ...validInput, occurredTimezone: "" }),
    ).toMatchObject({ success: false });
  });

  it("rejects a move-out date before the move-in date", () => {
    expect(
      parseHomeEntryInput({
        ...validInput,
        occurredEnd: "2024-01-01T00:00:00Z",
      }),
    ).toMatchObject({ success: false });
  });

  it("requires a move-out date before a move-out reason", () => {
    expect(
      parseHomeEntryInput({ ...validInput, occurredEnd: null }),
    ).toMatchObject({ success: false });
  });

  it("requires coordinates as an in-range pair", () => {
    expect(
      parseHomeEntryInput({ ...validInput, longitude: null }),
    ).toMatchObject({ success: false });
    expect(parseHomeEntryInput({ ...validInput, latitude: 91 })).toMatchObject({
      success: false,
    });
  });

  it("validates date precision and organization limits", () => {
    expect(
      parseHomeEntryInput({ ...validInput, datePrecision: "unknown" }),
    ).toMatchObject({ success: false });
    expect(
      parseHomeEntryInput({
        ...validInput,
        collectionNames: Array.from({ length: 21 }, (_, index) => `C${index}`),
      }),
    ).toMatchObject({ success: false });
  });

  it("validates Entry and Place identities", () => {
    expect(isHomeEntryIdentity(entryId, 2)).toBe(true);
    expect(isHomeEntryIdentity(entryId, null)).toBe(false);
    expect(isHomeEntryIdentity(null, null)).toBe(true);
    expect(
      parseHomeEntryInput({ ...validInput, placeId: "not-a-place" }),
    ).toMatchObject({ success: false });
  });
});
