import { describe, expect, it } from "vitest";
import { isPlaceIdentity, parsePlaceRecordInput } from "./place-record-input";

const placeId = "40000000-0000-4000-8000-000000000001";
const validPlace = {
  address: " 123 Walnut Street ",
  city: " Philadelphia ",
  country: " United States ",
  id: placeId,
  latitude: 39.9526,
  longitude: -75.1652,
  name: " Center City apartment ",
  notes: " First place on my own. ",
  region: " Pennsylvania ",
  revision: 3,
};

describe("parsePlaceRecordInput", () => {
  it("normalizes a complete Place edit", () => {
    const parsed = parsePlaceRecordInput(validPlace);

    expect(parsed.success).toBe(true);
    if (parsed.success) {
      expect(parsed.data).toMatchObject({
        address: "123 Walnut Street",
        city: "Philadelphia",
        country: "United States",
        latitude: 39.9526,
        longitude: -75.1652,
        name: "Center City apartment",
        notes: "First place on my own.",
        region: "Pennsylvania",
      });
    }
  });

  it("accepts a minimal new Place", () => {
    expect(
      parsePlaceRecordInput({
        ...validPlace,
        address: null,
        city: null,
        country: null,
        id: null,
        latitude: null,
        longitude: null,
        notes: null,
        region: null,
        revision: null,
      }),
    ).toMatchObject({ success: true });
  });

  it("requires paired in-range coordinates", () => {
    expect(
      parsePlaceRecordInput({ ...validPlace, longitude: null }),
    ).toMatchObject({ success: false });
    expect(
      parsePlaceRecordInput({ ...validPlace, latitude: 91 }),
    ).toMatchObject({ success: false });
    expect(
      parsePlaceRecordInput({ ...validPlace, longitude: Number.NaN }),
    ).toMatchObject({ success: false });
  });

  it("rejects invalid content and identity", () => {
    expect(parsePlaceRecordInput({ ...validPlace, name: " " })).toMatchObject({
      success: false,
    });
    expect(
      parsePlaceRecordInput({ ...validPlace, revision: null }),
    ).toMatchObject({ success: false });
  });

  it("validates matching create and edit identity", () => {
    expect(isPlaceIdentity(placeId, 2)).toBe(true);
    expect(isPlaceIdentity(placeId, null)).toBe(false);
    expect(isPlaceIdentity(null, null)).toBe(true);
  });
});
