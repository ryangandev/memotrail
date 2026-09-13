import { describe, it, expect } from "vitest";
import { validPhotoPlace } from "./photo-place";
describe("explicit photo Place drafts", () => {
  const draft = {
    kind: "new",
    attachmentId: "93000000-0000-4000-8000-000000000002",
    name: "Ski slope",
    latitude: 39.95,
    longitude: -75.166667,
  };
  it("requires a reviewed name and complete finite coordinates for new Places", () => {
    expect(validPhotoPlace(draft)).toBe(true);
    for (const values of [
      { name: " " },
      { name: "x".repeat(201) },
      { latitude: NaN },
      { latitude: 91 },
      { longitude: -181 },
      { longitude: null },
      { attachmentId: "" },
      { kind: "automatic" },
    ])
      expect(validPhotoPlace({ ...draft, ...values })).toBe(false);
    expect(validPhotoPlace({ ...draft, latitude: 0, longitude: 0 })).toBe(true);
  });
  it("existing Place choice requires identity and revision, not coordinate overwrites", () => {
    const existing = {
      kind: "existing",
      attachmentId: draft.attachmentId,
      placeId: "93000000-0000-4000-8000-000000000003",
      revision: 2,
    };
    expect(validPhotoPlace(existing)).toBe(true);
    for (const revision of [0, -1, 1.5, 1_000_000_000, undefined])
      expect(validPhotoPlace({ ...existing, revision })).toBe(false);
    expect(validPhotoPlace({ ...existing, placeId: "not-an-id" })).toBe(false);
  });
});
