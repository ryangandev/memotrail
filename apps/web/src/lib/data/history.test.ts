import { describe, it, expect } from "vitest";
import {
  historyDifferences,
  historyDateLabel,
  historyPage,
  historyTitle,
  validHistoryRestore,
  canRestoreHistorySnapshot,
  type HistorySnapshot,
} from "./history";
const snapshot = {
  id: "94000000-0000-4000-8000-000000000001",
  title: "Original",
  body: "Writing",
  item_kind: "entry" as const,
  item_subtype: "note",
  inbox_status: "unreviewed",
  revision: 1,
  deleted_at: null,
  occurred_start: null,
  occurred_end: null,
  date_precision: "unknown",
  occurred_label: null,
  occurred_timezone: "UTC",
} satisfies HistorySnapshot;
describe("Entry history", () => {
  it("allows the canonical schema 3 snapshot to be restored", () => {
    expect(canRestoreHistorySnapshot({ ...snapshot, history_schema: 3 })).toBe(
      true,
    );
  });
  it.each([undefined, null, 0, 1, 2, 4, "3"])(
    "blocks unsupported or missing history schema %s",
    (history_schema) => {
      expect(
        canRestoreHistorySnapshot({
          ...snapshot,
          history_schema,
        } as HistorySnapshot),
      ).toBe(false);
    },
  );
  it("does not allow restoration without a selected snapshot", () => {
    expect(canRestoreHistorySnapshot(undefined)).toBe(false);
  });
  it("formats only known date precision in the original timezone", () => {
    expect(
      historyDateLabel({
        ...snapshot,
        occurred_start: "2021-01-01T01:00:00Z",
        occurred_timezone: "America/New_York",
        date_precision: "year",
      }),
    ).toBe("2020");
    expect(historyDateLabel({ ...snapshot, occurred_label: "Age 17" })).toBe(
      "Age 17",
    );
    expect(historyDateLabel(snapshot)).toBe("Unknown");
  });
  it("requires a prior version and expected current revision", () => {
    expect(validHistoryRestore(snapshot.id, 1, 2)).toBe(true);
    expect(validHistoryRestore(snapshot.id, 2, 2)).toBe(false);
    expect(validHistoryRestore(snapshot.id, 0, 2)).toBe(false);
    expect(validHistoryRestore("invalid", 1, 2)).toBe(false);
  });
  it("does not imply unrecorded legacy relationships will be restored", () => {
    expect(
      historyDifferences(
        { ...snapshot, collections: [{ id: "new" }] },
        snapshot,
      ),
    ).toEqual([]);
  });
  it("compares writing and explicitly recorded empty relations", () => {
    expect(
      historyDifferences(
        { ...snapshot, body: "New", collections: [{ id: "new" }] },
        { ...snapshot, collections: [] },
      ),
    ).toEqual(["Writing", "Collections"]);
  });
  it("compares normalized Home and Vehicle content without client filtering", () => {
    const previous = {
      ...snapshot,
      places: [{ place_id: "maple", relationship: "home", name: "Maple" }],
      timeline_items: [
        { track_id: "homes", timeline_kind: "stage", sort_order: 7 },
      ],
      home: {
        entry_id: snapshot.id,
        place_id: "maple",
        move_in_reason: "Study",
      },
      vehicle: { entry_id: snapshot.id, color: "Blue" },
    };
    expect(
      historyDifferences({ ...previous, title: "Renamed" }, previous),
    ).toEqual(["Title"]);
    expect(
      historyDifferences(
        { ...previous, home: { ...previous.home, move_in_reason: "Work" } },
        previous,
      ),
    ).toEqual(["Home details"]);
    expect(
      historyDifferences(
        { ...previous, vehicle: { ...previous.vehicle, color: "Red" } },
        previous,
      ),
    ).toEqual(["Vehicle details"]);
    expect(historyDifferences(previous, previous)).toEqual([]);
  });
  it.each([
    ["people", "person_id", "People links"],
    ["places", "place_id", "Location links"],
    ["timeline_items", "track_id", "Timeline placement"],
    ["links", "target_entry_id", "Entry links"],
    ["attachments", "id", "Photos"],
  ])("retains real membership differences for %s", (field, identity, label) => {
    expect(
      historyDifferences(
        { ...snapshot, [field]: [{ [identity]: "new" }] },
        { ...snapshot, [field]: [{ [identity]: "old" }] },
      ),
    ).toEqual([label]);
  });
  it("preserves authored metadata dates as comparable content", () => {
    expect(
      historyDifferences(
        { ...snapshot, metadata: { created_at: "2026-10-01" } },
        { ...snapshot, metadata: { created_at: "2026-09-30" } },
      ),
    ).toEqual(["Other metadata"]);
  });
  it("compares formatting as part of the writing, not other metadata", () => {
    const bold = {
      document: {
        content: [
          {
            content: [
              { marks: [{ type: "bold" }], text: "Writing", type: "text" },
            ],
            type: "paragraph",
          },
        ],
        type: "doc",
      },
      text: "Writing",
      version: 1,
    };
    const formatted = {
      ...snapshot,
      metadata: { body_rich: bold, source: "web" },
    };
    const plain = { ...snapshot, metadata: { source: "web" } };
    expect(historyDifferences(plain, formatted)).toEqual(["Writing"]);
    expect(historyDifferences({ ...plain, body: "Edited" }, formatted)).toEqual(
      ["Writing"],
    );
    expect(
      historyDifferences(
        { ...formatted, metadata: { body_rich: bold, source: "ios" } },
        formatted,
      ),
    ).toEqual(["Other metadata"]);
    expect(historyDifferences(formatted, formatted)).toEqual([]);
  });
  it("handles body-only and empty titles", () => {
    expect(historyTitle({ title: null, body: "  学习记录 " })).toBe("学习记录");
    expect(historyTitle({ title: null })).toBe("Untitled item");
  });
  it("bounds pagination and preserves valid pages", () => {
    expect(historyPage("3", 5)).toBe(3);
    for (const value of ["0", "-1", "6", "1.5", "bad"])
      expect(historyPage(value, 5)).toBe(1);
  });
});
