import { describe, expect, it } from "vitest";
import { vi } from "vitest";

vi.mock("server-only", () => ({}));

import { parseGeoapifyResponse } from "./geoapify";

describe("Geoapify location normalization", () => {
  it("keeps the durable provider identity and useful address facts", () => {
    expect(
      parseGeoapifyResponse({
        results: [
          {
            place_id: "51bf7-test",
            name: "Philadelphia Museum of Art",
            formatted:
              "2600 Benjamin Franklin Parkway, Philadelphia, PA 19130, USA",
            address_line1: "2600 Benjamin Franklin Parkway",
            city: "Philadelphia",
            state: "Pennsylvania",
            postcode: "19130",
            country: "United States",
            country_code: "us",
            lat: 39.9656,
            lon: -75.1809,
            result_type: "amenity",
            timezone: { name: "America/New_York" },
            rank: { confidence: 0.97, match_type: "full_match" },
            datasource: { name: "openstreetmap" },
          },
        ],
      }),
    ).toEqual([
      expect.objectContaining({
        provider: "geoapify",
        providerLocationId: "51bf7-test",
        formattedAddress:
          "2600 Benjamin Franklin Parkway, Philadelphia, PA 19130, USA",
        postalCode: "19130",
        timezone: "America/New_York",
        latitude: 39.9656,
        longitude: -75.1809,
      }),
    ]);
  });

  it("drops provider results without stable identity or coordinates", () => {
    expect(
      parseGeoapifyResponse({
        results: [
          { formatted: "No provider identity", lat: 1, lon: 2 },
          { place_id: "bad-coordinate", formatted: "Bad", lat: 91, lon: 2 },
        ],
      }),
    ).toEqual([]);
  });
});
