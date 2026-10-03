import { describe, expect, it } from "vitest";
import {
  existingLocationFromRow,
  locationDisplayLabel,
  savedLocationSelection,
  validLocationSelection,
  type ProviderLocation,
} from "./location";

describe("Location selections", () => {
  it("parses an existing owner-scoped Location row", () => {
    expect(
      existingLocationFromRow({
        id: "95000000-0000-4000-8000-000000000001",
        revision: 2,
        name: "Pine Street",
        formatted_address: "10 Pine Street, Philadelphia, PA",
        address: "10 Pine Street",
        city: "Philadelphia",
        region: "Pennsylvania",
        postal_code: "19107",
        country: "United States",
        country_code: "us",
        latitude: 39.95,
        longitude: -75.16,
        timezone_id: "America/New_York",
        result_type: "building",
      }),
    ).toMatchObject({ kind: "existing", name: "Pine Street", revision: 2 });
  });

  it("rejects incomplete coordinates and unknown providers", () => {
    const base = {
      kind: "provider",
      provider: "geoapify",
      providerLocationId: "provider-id",
      name: "Pine Street",
      formattedAddress: "10 Pine Street",
      address: "10 Pine Street",
      city: null,
      region: null,
      postalCode: null,
      country: null,
      countryCode: null,
      latitude: 39.95,
      longitude: -75.16,
      timezone: null,
      resultType: "building",
      confidence: null,
      matchType: null,
      dataSource: null,
    };
    expect(validLocationSelection(base)).toBe(true);
    expect(validLocationSelection({ ...base, provider: "other" })).toBe(false);
    expect(validLocationSelection({ ...base, longitude: null })).toBe(false);
  });

  it("shows address facts instead of the legacy custom Location name", () => {
    const location = existingLocationFromRow({
      id: "95000000-0000-4000-8000-000000000001",
      revision: 1,
      name: "The old personal label",
      formatted_address: "10 Pine Street, Philadelphia, PA",
      address: "10 Pine Street",
      city: "Philadelphia",
      latitude: 39.95,
      longitude: -75.16,
    });
    expect(location).not.toBeNull();
    expect(locationDisplayLabel(location!)).toBe(
      "10 Pine Street, Philadelphia, PA",
    );
    expect(locationDisplayLabel({ ...location!, formattedAddress: null })).toBe(
      "10 Pine Street, Philadelphia",
    );
  });

  it("holds a saved provider choice as the record's own Location", () => {
    const provider: ProviderLocation = {
      kind: "provider",
      provider: "geoapify",
      providerLocationId: "provider-id",
      name: "10 Pine Street, Philadelphia, PA",
      formattedAddress: "10 Pine Street, Philadelphia, PA",
      address: "10 Pine Street",
      city: "Philadelphia",
      region: "Pennsylvania",
      postalCode: "19107",
      country: "United States",
      countryCode: "us",
      latitude: 39.95261234,
      longitude: -75.16529876,
      timezone: "America/New_York",
      resultType: "building",
      confidence: 0.99,
      matchType: "full_match",
      dataSource: "openstreetmap",
    };
    const saved = savedLocationSelection(
      provider,
      "95000000-0000-4000-8000-000000000002",
    );

    expect(saved).toEqual({
      kind: "existing",
      id: "95000000-0000-4000-8000-000000000002",
      revision: 1,
      name: "10 Pine Street, Philadelphia, PA",
      formattedAddress: "10 Pine Street, Philadelphia, PA",
      address: "10 Pine Street",
      city: "Philadelphia",
      region: "Pennsylvania",
      postalCode: "19107",
      country: "United States",
      countryCode: "us",
      latitude: 39.95261234,
      longitude: -75.16529876,
      timezone: "America/New_York",
      resultType: "building",
    });
    expect(validLocationSelection(saved)).toBe(true);
    expect(locationDisplayLabel(saved!)).toBe(locationDisplayLabel(provider));
  });

  it("follows the saved snapshot identity and clears an unsaved Location", () => {
    const existing = existingLocationFromRow({
      id: "95000000-0000-4000-8000-000000000001",
      revision: 2,
      name: "10 Pine Street",
      address: "10 Pine Street",
      latitude: null,
      longitude: null,
    })!;

    expect(
      savedLocationSelection(existing, "95000000-0000-4000-8000-000000000003"),
    ).toEqual({ ...existing, id: "95000000-0000-4000-8000-000000000003" });
    expect(savedLocationSelection(existing, null)).toBeNull();
    expect(
      savedLocationSelection(null, "95000000-0000-4000-8000-000000000003"),
    ).toBeNull();
  });
});
