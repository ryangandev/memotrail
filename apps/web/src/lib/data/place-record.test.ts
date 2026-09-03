import { describe, expect, it } from "vitest";
import {
  parsePlaceLinkOptions,
  parsePlaceRows,
  placeCoordinateLabel,
  placeCover,
  placeLocationLabel,
} from "./place-record";

const attachment = {
  bucket_id: "entry-media",
  byte_size: 1234,
  created_at: "2026-09-03T10:00:00Z",
  id: "60000000-0000-4000-8000-000000000001",
  mime_type: "image/jpeg",
  object_path: "owner/entry/photo.jpg",
  original_filename: "photo.jpg",
  pixel_height: 1200,
  pixel_width: 1600,
};

const row = {
  address: "123 Walnut Street",
  city: "Philadelphia",
  country: "United States",
  created_at: "2026-09-01T10:00:00Z",
  home_count: 1,
  latitude: 39.9526,
  linked_entries: [
    {
      attachments: [attachment],
      body: "The first apartment I chose for myself.",
      date_precision: "range",
      entry_type: "home",
      id: "40000000-0000-4000-8000-000000000002",
      inbox_status: "organized",
      occurred_end: null,
      occurred_label: "My twenties",
      occurred_start: "2025-01-01T20:00:00Z",
      occurred_timezone: "America/Los_Angeles",
      relationship: "home",
      revision: 2,
      title: "Center City home",
      updated_at: "2026-09-02T10:00:00Z",
    },
  ],
  linked_entry_count: 1,
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
  it("parses location, relationship, count, and private photo context", () => {
    const places = parsePlaceRows([row]);

    expect(places).toHaveLength(1);
    expect(places?.[0]).toMatchObject({
      homeCount: 1,
      linkedEntries: [
        {
          attachments: [{ imageUrl: null, mimeType: "image/jpeg" }],
          relationship: "home",
        },
      ],
      linkedEntryCount: 1,
      totalCount: 1,
    });
  });

  it("rejects malformed Place, relationship, and attachment rows", () => {
    expect(parsePlaceRows([{ ...row, latitude: "39.9" }])).toBeNull();
    expect(
      parsePlaceRows([{ ...row, linked_entries: [{ id: "incomplete" }] }]),
    ).toBeNull();
    expect(
      parsePlaceRows([
        {
          ...row,
          linked_entries: [
            {
              ...row.linked_entries[0],
              attachments: [{ mime_type: "image/gif" }],
            },
          ],
        },
      ]),
    ).toBeNull();
  });

  it("formats location, coordinates, and cover context", () => {
    const place = parsePlaceRows([row])?.[0];
    expect(place).toBeDefined();
    if (!place) return;

    expect(placeLocationLabel(place)).toBe(
      "123 Walnut Street · Philadelphia, Pennsylvania, United States",
    );
    expect(placeCoordinateLabel(place)).toBe("39.9526°N, 75.1652°W");
    expect(placeCover(place)?.objectPath).toBe("owner/entry/photo.jpg");
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

  it("parses selectable Entry options with title fallbacks", () => {
    expect(
      parsePlaceLinkOptions([
        {
          body: "A useful memory from the neighborhood.",
          entry_type: "standard",
          id: "40000000-0000-4000-8000-000000000003",
          title: null,
          updated_at: "2026-09-03T10:00:00Z",
        },
      ]),
    ).toEqual([
      {
        entryType: "standard",
        id: "40000000-0000-4000-8000-000000000003",
        title: "A useful memory from the neighborhood.",
        updatedAt: "2026-09-03T10:00:00Z",
      },
    ]);
    expect(parsePlaceLinkOptions([{ id: "incomplete" }])).toBeNull();
  });
});
