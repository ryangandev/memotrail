import { describe, expect, it } from "vitest";
import { parseHomeResurfacedMemory } from "./home-resurfacing";

const entry = {
  attachments: [
    {
      attachment_id: "85000000-0000-0000-0000-000000000001",
      bucket_id: "entry-media",
      byte_size: 512,
      mime_type: "image/jpeg",
      object_path: "owner/entry/photo.jpg",
      original_filename: "photo.jpg",
      pixel_height: 800,
      pixel_width: 1200,
    },
  ],
  body: "A memory worth seeing again.",
  created_at: "2025-09-03T17:00:00Z",
  date_precision: "day",
  entry_id: "87000000-0000-0000-0000-000000000001",
  item_kind: "entry",
  item_subtype: "first_time",
  inbox_status: "organized",
  occurred_end: null,
  occurred_label: null,
  occurred_start: "2025-09-03T17:00:00Z",
  occurred_timezone: "America/Los_Angeles",
  revision: 2,
  tag_names: ["snow"],
  title: "First time skiing",
  updated_at: "2025-09-04T17:00:00Z",
};

describe("Home resurfacing response", () => {
  it("accepts an On This Day memory with complete Entry context", () => {
    const memory = parseHomeResurfacedMemory([
      { ...entry, resurfacing_kind: "on_this_day", years_ago: 1 },
    ]);

    expect(memory).toMatchObject({
      id: entry.entry_id,
      resurfacingKind: "on_this_day",
      tagNames: ["snow"],
      yearsAgo: 1,
    });
    expect(memory?.attachments[0]).toMatchObject({
      imageUrl: null,
      mimeType: "image/jpeg",
      objectPath: "owner/entry/photo.jpg",
    });
  });

  it("accepts an archive rotation without an anniversary count", () => {
    expect(
      parseHomeResurfacedMemory([
        {
          ...entry,
          resurfacing_kind: "from_your_archive",
          years_ago: null,
        },
      ]),
    ).toMatchObject({
      resurfacingKind: "from_your_archive",
      yearsAgo: null,
    });
  });

  it("treats an empty response as no memory for today", () => {
    expect(parseHomeResurfacedMemory([])).toBeNull();
  });

  it("rejects unsupported selection kinds and invalid anniversary counts", () => {
    expect(
      parseHomeResurfacedMemory([
        { ...entry, resurfacing_kind: "random", years_ago: null },
      ]),
    ).toBeNull();
    expect(
      parseHomeResurfacedMemory([
        { ...entry, resurfacing_kind: "on_this_day", years_ago: 0 },
      ]),
    ).toBeNull();
  });

  it("rejects unreviewed or undated Entries", () => {
    expect(
      parseHomeResurfacedMemory([
        {
          ...entry,
          inbox_status: "unreviewed",
          resurfacing_kind: "on_this_day",
          years_ago: 1,
        },
      ]),
    ).toBeNull();
    expect(
      parseHomeResurfacedMemory([
        {
          ...entry,
          occurred_start: null,
          resurfacing_kind: "on_this_day",
          years_ago: 1,
        },
      ]),
    ).toBeNull();
  });

  it("rejects malformed attachment metadata", () => {
    expect(
      parseHomeResurfacedMemory([
        {
          ...entry,
          attachments: [{ mime_type: "image/jpeg" }],
          resurfacing_kind: "on_this_day",
          years_ago: 1,
        },
      ]),
    ).toBeNull();
  });
});
