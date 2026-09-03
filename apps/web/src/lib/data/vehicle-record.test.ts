import { describe, expect, it } from "vitest";
import {
  parseVehicleRows,
  vehicleDurationLabel,
  vehicleFactsLabel,
  vehicleRangeLabel,
} from "./vehicle-record";

const row = {
  attachments: [
    {
      bucket_id: "entry-media",
      byte_size: 1234,
      created_at: "2026-09-03T10:00:00Z",
      id: "60000000-0000-4000-8000-000000000001",
      mime_type: "image/jpeg",
      object_path: "owner/entry/photo.jpg",
      original_filename: "photo.jpg",
      pixel_height: 1200,
      pixel_width: 1600,
    },
  ],
  body: "The electric road-trip years.",
  collection_names: ["Vehicles"],
  color: "Midnight Silver",
  date_precision: "month",
  entry_id: "40000000-0000-4000-8000-000000000001",
  make: "Tesla",
  model: "Model Y",
  model_year: 2021,
  occurred_end: null,
  occurred_label: null,
  occurred_start: "2020-03-12T12:00:00Z",
  occurred_timezone: "America/New_York",
  revision: 2,
  tag_names: ["electric"],
  timeline_track_id: "70000000-0000-4000-8000-000000000001",
  timeline_track_name: "Vehicles",
  title: "Bluebird EV",
  total_count: 1,
  updated_at: "2026-09-03T10:00:00Z",
};

describe("Vehicle records", () => {
  it("parses the complete Vehicles response", () => {
    const records = parseVehicleRows([row]);

    expect(records).toHaveLength(1);
    expect(records?.[0]).toMatchObject({
      attachments: [{ imageUrl: null, mimeType: "image/jpeg" }],
      make: "Tesla",
      model: "Model Y",
      timelineTrackName: "Vehicles",
    });
  });

  it("rejects malformed Vehicle and attachment rows", () => {
    expect(parseVehicleRows([{ ...row, occurred_start: null }])).toBeNull();
    expect(parseVehicleRows([{ ...row, model_year: 2020.5 }])).toBeNull();
    expect(
      parseVehicleRows([{ ...row, attachments: [{ mime_type: "image/gif" }] }]),
    ).toBeNull();
  });

  it("presents current date and duration context", () => {
    const vehicle = parseVehicleRows([row])?.[0];
    expect(vehicle).toBeDefined();
    if (!vehicle) return;

    expect(vehicleRangeLabel(vehicle)).toBe("Since Mar 2020");
    expect(
      vehicleDurationLabel(vehicle, new Date("2026-09-03T12:00:00Z")),
    ).toBe("6 years 5 months");
  });

  it("uses a human label and completed range when provided", () => {
    const vehicle = parseVehicleRows([
      {
        ...row,
        occurred_end: "2026-08-31T12:00:00Z",
        occurred_label: "The California road-trip years",
      },
    ])?.[0];
    expect(vehicle).toBeDefined();
    if (!vehicle) return;

    expect(vehicleRangeLabel(vehicle)).toBe("The California road-trip years");
    expect(vehicleDurationLabel(vehicle)).toBe("6 years 5 months");
  });

  it("builds a compact facts label without empty separators", () => {
    const complete = parseVehicleRows([row])?.[0];
    const incomplete = parseVehicleRows([
      { ...row, color: null, make: null, model: null, model_year: null },
    ])?.[0];

    expect(complete && vehicleFactsLabel(complete)).toBe(
      "2021 Tesla Model Y · Midnight Silver",
    );
    expect(incomplete && vehicleFactsLabel(incomplete)).toBe(
      "Details not recorded",
    );
  });

  it("falls back to UTC when a legacy timezone is invalid", () => {
    const vehicle = parseVehicleRows([
      { ...row, occurred_timezone: "Invalid/Zone" },
    ])?.[0];
    expect(vehicle).toBeDefined();
    if (!vehicle) return;

    expect(vehicleRangeLabel(vehicle)).toBe("Since Mar 2020");
  });
});
