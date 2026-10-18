import { describe, expect, it } from "vitest";
import { goalTargetDate, goalTargetLabel, parseGoalRows } from "./goal-record";

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
  body: "Learn the landscape, then decide.",
  created_at: "2026-09-01T10:00:00Z",
  entry_id: "40000000-0000-4000-8000-000000000001",
  related_entries: [
    {
      body: "Sailed across the bay.",
      date_precision: "day",
      item_kind: "entry",
      item_subtype: "entry",
      id: "40000000-0000-4000-8000-000000000002",
      occurred_end: null,
      occurred_label: null,
      occurred_start: "2026-08-01T12:00:00Z",
      occurred_timezone: "America/Los_Angeles",
      relationship: "achievement",
      revision: 1,
      title: "First sail across the bay",
      updated_at: "2026-08-01T12:00:00Z",
    },
  ],
  revision: 3,
  status: "active",
  tag_names: ["sailing"],
  target_date: "2030-06-15",
  title: "Learn to sail",
  total_count: 1,
  updated_at: "2026-09-03T10:00:00Z",
};

describe("Goal records", () => {
  it("parses a complete Goal response", () => {
    const goals = parseGoalRows([row]);

    expect(goals).toHaveLength(1);
    expect(goals?.[0]).toMatchObject({
      attachments: [{ imageUrl: null, mimeType: "image/jpeg" }],
      relatedEntries: [
        {
          itemKind: "entry",
          itemSubtype: "entry",
          relationship: "achievement",
          title: "First sail across the bay",
        },
      ],
      status: "active",
      targetDate: "2030-06-15",
    });
  });

  it("names an untitled First Time by its date", () => {
    const [entry] = parseGoalRows([
      { ...row, related_entries: [{ ...row.related_entries[0], title: "" }] },
    ])![0].relatedEntries;
    expect(entry.title).toBe("Saturday, August 1, 2026");
  });

  it("rejects retired states and malformed Goal, relationship, and attachment rows", () => {
    expect(parseGoalRows([{ ...row, status: "paused" }])).toBeNull();
    expect(parseGoalRows([{ ...row, status: "considering" }])).toBeNull();
    expect(
      parseGoalRows([{ ...row, related_entries: [{ id: "missing-fields" }] }]),
    ).toBeNull();
    expect(
      parseGoalRows([{ ...row, attachments: [{ mime_type: "image/gif" }] }]),
    ).toBeNull();
  });

  it("presents an optional target", () => {
    const goal = parseGoalRows([row])?.[0];
    expect(goal).toBeDefined();
    if (!goal) return;

    expect(goalTargetLabel(goal)).toBe("Target Jun 15, 2030");
    expect(goalTargetDate(goal)).toBe("Jun 15, 2030");
    expect(goalTargetDate({ ...goal, targetDate: null })).toBeNull();
    expect(goalTargetLabel({ ...goal, targetDate: null })).toBe(
      "No target date",
    );
  });
});
