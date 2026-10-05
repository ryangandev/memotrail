import { describe, expect, it } from "vitest";
import { validPhotoLocation } from "./photo-location";

describe("photo Location drafts", () => {
  const draft = {
    attachmentId: "93000000-0000-4000-8000-000000000002",
    latitude: 39.95,
    longitude: -75.166667,
  };

  it("requires the photo and complete finite coordinates", () => {
    expect(validPhotoLocation(draft)).toBe(true);
    expect(validPhotoLocation({ ...draft, latitude: 0, longitude: 0 })).toBe(
      true,
    );
    for (const values of [
      { latitude: NaN },
      { latitude: 91 },
      { longitude: -181 },
      { longitude: null },
      { attachmentId: "" },
      { attachmentId: "not-a-photo" },
    ])
      expect(validPhotoLocation({ ...draft, ...values })).toBe(false);
    expect(validPhotoLocation(null)).toBe(false);
  });
});
