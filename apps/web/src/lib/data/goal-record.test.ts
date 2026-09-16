import { describe, expect, it } from "vitest";
import {
  goalTargetLabel,
  isBucketListGoal,
  parseGoalLinkOptions,
  parseGoalRows,
} from "./goal-record";

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
  collection_names: ["Bucket List"],
  created_at: "2026-09-01T10:00:00Z",
  entry_id: "40000000-0000-4000-8000-000000000001",
  horizon: "long_term",
  related_entries: [
    {
      body: "A useful sailing lesson.",
      item_kind: "writing",
      item_subtype: "lesson",
      id: "40000000-0000-4000-8000-000000000002",
      occurred_label: null,
      occurred_start: "2026-08-01T12:00:00Z",
      occurred_timezone: "America/Los_Angeles",
      relationship: "related",
      revision: 1,
      title: "First sailing lesson",
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
  it("preserves Bucket List behavior after a Collection is renamed", () => {
    const goal = parseGoalRows([
      {
        ...row,
        collection_names: ["Someday adventures"],
        is_bucket_list: true,
      },
    ])?.[0];
    expect(goal && isBucketListGoal(goal)).toBe(true);
    const removed = parseGoalRows([{ ...row, is_bucket_list: false }])?.[0];
    expect(removed && isBucketListGoal(removed)).toBe(false);
  });
  it("parses a complete Goal response", () => {
    const goals = parseGoalRows([row]);

    expect(goals).toHaveLength(1);
    expect(goals?.[0]).toMatchObject({
      attachments: [{ imageUrl: null, mimeType: "image/jpeg" }],
      horizon: "long_term",
      relatedEntries: [
        {
          itemKind: "writing",
          itemSubtype: "lesson",
          relationship: "related",
        },
      ],
      status: "active",
      targetDate: "2030-06-15",
    });
  });

  it("rejects malformed Goal, relationship, and attachment rows", () => {
    expect(parseGoalRows([{ ...row, horizon: "weekly" }])).toBeNull();
    expect(
      parseGoalRows([{ ...row, related_entries: [{ id: "missing-fields" }] }]),
    ).toBeNull();
    expect(
      parseGoalRows([{ ...row, attachments: [{ mime_type: "image/gif" }] }]),
    ).toBeNull();
  });

  it("presents optional target and Bucket List context", () => {
    const goal = parseGoalRows([row])?.[0];
    expect(goal).toBeDefined();
    if (!goal) return;

    expect(goalTargetLabel(goal)).toBe("Target Jun 15, 2030");
    expect(isBucketListGoal(goal)).toBe(true);
    expect(goalTargetLabel({ ...goal, targetDate: null })).toBe(
      "No target date",
    );
  });

  it("parses selectable related Entry options", () => {
    expect(
      parseGoalLinkOptions([
        {
          item_kind: "writing",
          item_subtype: "reflection",
          body: null,
          id: "40000000-0000-4000-8000-000000000002",
          title: "An earlier reflection",
          updated_at: "2026-09-03T10:00:00Z",
        },
      ]),
    ).toEqual([
      {
        id: "40000000-0000-4000-8000-000000000002",
        itemKind: "writing",
        itemSubtype: "reflection",
        title: "An earlier reflection",
        updatedAt: "2026-09-03T10:00:00Z",
      },
    ]);
    expect(parseGoalLinkOptions([{ id: "incomplete" }])).toBeNull();
  });
});
