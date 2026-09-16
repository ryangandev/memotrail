import { describe, it, expect } from "vitest";
import {
  historyDifferences,
  historyDateLabel,
  historyPage,
  historyTitle,
  validHistoryRestore,
  type HistorySnapshot,
} from "./history";
const snapshot = {
  id: "94000000-0000-4000-8000-000000000001",
  title: "Original",
  body: "Writing",
  item_kind: "writing" as const,
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
  it("handles body-only and empty titles", () => {
    expect(historyTitle({ title: null, body: "  学习记录 " })).toBe("学习记录");
    expect(historyTitle({ title: null })).toBe("Untitled Entry");
  });
  it("bounds pagination and preserves valid pages", () => {
    expect(historyPage("3", 5)).toBe(3);
    for (const value of ["0", "-1", "6", "1.5", "bad"])
      expect(historyPage(value, 5)).toBe(1);
  });
});
