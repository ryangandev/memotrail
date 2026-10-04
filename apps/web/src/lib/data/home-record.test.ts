import { describe, expect, it } from "vitest";
import {
  homeDurationLabel,
  homeLocationLabel,
  homeRangeLabel,
  parseHomeRows,
} from "./home-record";

const row = {
  address: "456 Elm Street",
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
  body: "A quieter home.",
  city: "San Francisco",
  country: "United States",
  date_precision: "month",
  entry_id: "40000000-0000-4000-8000-000000000001",
  latitude: 37.774929,
  longitude: -122.419418,
  move_in_reason: "A new chapter.",
  move_out_reason: null,
  occurred_end: null,
  occurred_label: null,
  occurred_start: "2025-06-01T19:00:00Z",
  occurred_timezone: "America/Los_Angeles",
  place_id: "50000000-0000-4000-8000-000000000001",
  place_name: "California home",
  place_notes: "Walkable and quiet.",
  region: "California",
  revision: 2,
  tag_names: ["California"],
  timeline_track_id: "70000000-0000-4000-8000-000000000001",
  timeline_track_name: "Homes",
  title: "California home",
  total_count: 1,
  updated_at: "2026-09-03T10:00:00Z",
};

describe("Home records", () => {
  it.each(["age", "approximate", "unknown"])(
    "reads unanchored %s rows without hiding the archive",
    (date_precision) => {
      const records = parseHomeRows([
        {
          ...row,
          date_precision,
          occurred_start: null,
          occurred_end: null,
          occurred_timezone: null,
          occurred_label: "During college",
        },
      ]);
      expect(records).toHaveLength(1);
      expect(homeDurationLabel(records![0])).toBe("Duration unavailable");
      expect(homeRangeLabel(records![0])).toBe("During college");
    },
  );
  it("parses the complete Homes response", () => {
    const records = parseHomeRows([row]);

    expect(records).toHaveLength(1);
    expect(records?.[0]).toMatchObject({
      address: "456 Elm Street",
      attachments: [{ imageUrl: null, mimeType: "image/jpeg" }],
      placeName: "California home",
      timelineTrackName: "Homes",
    });
  });

  it("keeps a Home with no Location visible", () => {
    const home = parseHomeRows([
      {
        ...row,
        place_id: null,
        place_name: null,
        address: null,
        city: null,
        region: null,
        country: null,
        latitude: null,
        longitude: null,
      },
    ])?.[0];
    expect(home?.placeId).toBeNull();
    expect(home && homeLocationLabel(home)).toBe("Location not added");
  });

  it("rejects malformed Home and attachment rows", () => {
    expect(parseHomeRows([{ ...row, occurred_start: null }])).toBeNull();
    expect(
      parseHomeRows([{ ...row, attachments: [{ mime_type: "image/gif" }] }]),
    ).toBeNull();
  });

  it("presents location, range, and current duration context", () => {
    const home = parseHomeRows([row])?.[0];
    expect(home).toBeDefined();
    if (!home) return;

    expect(homeLocationLabel(home)).toBe(
      "San Francisco, California, United States",
    );
    expect(homeRangeLabel(home)).toBe("Since Jun 2025");
    expect(homeDurationLabel(home, new Date("2026-09-03T12:00:00Z"))).toBe(
      "About 1 year 3 months",
    );
  });

  it("uses a human label and completed range when provided", () => {
    const home = parseHomeRows([
      {
        ...row,
        occurred_end: "2026-08-31T19:00:00Z",
        occurred_label: "Ages 25 to 26",
      },
    ])?.[0];
    expect(home).toBeDefined();
    if (!home) return;

    expect(homeRangeLabel(home)).toBe("Ages 25 to 26");
    expect(homeDurationLabel(home)).toBe("About 1 year 2 months");
  });
});
