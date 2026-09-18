import { describe, expect, it } from "vitest";
import { parsePlaceRows, placeLocationLabel } from "./place-record";

const row = {
  address: "123 Walnut Street",
  city: "Philadelphia",
  country: "United States",
  created_at: "2026-09-01T10:00:00Z",
  home_count: 0,
  latitude: 39.9526,
  linked_entries: [],
  linked_entry_count: 0,
  longitude: -75.1652,
  name: "Center City apartment",
  notes: "First place on my own.",
  place_id: "40000000-0000-4000-8000-000000000001",
  region: "Pennsylvania",
  revision: 3,
  total_count: "1",
  updated_at: "2026-09-03T10:00:00Z",
};

describe("Place records", () => {
  it("parses a standalone personal Place", () => {
    const places = parsePlaceRows([row]);

    expect(places).toHaveLength(1);
    expect(places?.[0]).toMatchObject({
      name: "Center City apartment",
      notes: "First place on my own.",
      totalCount: 1,
    });
  });

  it("rejects malformed standalone Place rows", () => {
    expect(parsePlaceRows([{ ...row, latitude: "39.9" }])).toBeNull();
    expect(parsePlaceRows([{ ...row, revision: "3" }])).toBeNull();
  });

  it("formats optional address context", () => {
    const place = parsePlaceRows([row])?.[0];
    expect(place).toBeDefined();
    if (!place) return;

    expect(placeLocationLabel(place)).toBe(
      "123 Walnut Street · Philadelphia, Pennsylvania, United States",
    );
    expect(
      placeLocationLabel({
        ...place,
        address: null,
        city: null,
        country: null,
        region: null,
      }),
    ).toBe("Location details not added");
  });
});
