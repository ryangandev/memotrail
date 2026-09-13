import { describe, expect, it, vi } from "vitest";
import {
  emptyTrashResultMessage,
  parseEmptyTrashSnapshot,
  runEmptyTrash,
} from "./empty-trash";
const row = {
  item_kind: "entry",
  item_id: "95000000-0000-4000-8000-000000000001",
  deleted_at: "2026-09-01T12:00:00.123456Z",
  revision: 2,
};
describe("confirmed Empty Trash", () => {
  it("preserves exact timestamps and kind identities without content", () => {
    expect(
      parseEmptyTrashSnapshot([
        row,
        { ...row, item_kind: "attachment", revision: null },
      ]),
    ).toEqual([
      {
        itemKind: "entry",
        itemId: row.item_id,
        deletedAt: row.deleted_at,
        revision: 2,
      },
      {
        itemKind: "attachment",
        itemId: row.item_id,
        deletedAt: row.deleted_at,
        revision: null,
      },
    ]);
  });
  it.each([
    null,
    {},
    [row, row],
    [{ ...row, revision: 0 }],
    [{ ...row, item_kind: "unknown" }],
    [{ ...row, deleted_at: "tomorrow" }],
    [{ ...row, item_id: "wrong" }],
    Array(10001).fill(row),
  ])("rejects an invalid complete manifest", (value) => {
    expect(parseEmptyTrashSnapshot(value)).toBeNull();
  });
  it("accepts a genuinely empty snapshot", () =>
    expect(parseEmptyTrashSnapshot([])).toEqual([]));
  it("deletes only the supplied targets and reports each confirmed success", async () => {
    const targets = parseEmptyTrashSnapshot([
      row,
      { ...row, item_kind: "habit" },
    ])!;
    const remove = vi.fn(async () => true),
      progress = vi.fn();
    expect(await runEmptyTrash(targets, remove, progress)).toEqual({
      deleted: 2,
      total: 2,
      complete: true,
    });
    expect(remove.mock.calls).toHaveLength(2);
    expect(progress.mock.calls).toEqual([[1], [2]]);
  });
  it.each([false, "throw"])(
    "stops on an uncertain or changed item instead of deleting later targets: %s",
    async (mode) => {
      const targets = parseEmptyTrashSnapshot([
        row,
        { ...row, item_kind: "habit" },
        { ...row, item_kind: "person" },
      ])!;
      const remove = vi
        .fn()
        .mockResolvedValueOnce(true)
        .mockImplementationOnce(async () => {
          if (mode === "throw") throw new Error("lost response");
          return false;
        });
      expect(await runEmptyTrash(targets, remove, () => {})).toEqual({
        deleted: 1,
        total: 3,
        complete: false,
      });
      expect(remove).toHaveBeenCalledTimes(2);
    },
  );
  it("does not start another deletion after leaving the view", async () => {
    const remove = vi.fn(async () => true);
    expect(
      await runEmptyTrash(
        parseEmptyTrashSnapshot([row])!,
        remove,
        () => {},
        () => false,
      ),
    ).toMatchObject({ deleted: 0, complete: false });
    expect(remove).not.toHaveBeenCalled();
  });
  it("does not claim all of Trash is empty or an uncertain deletion failed", () => {
    expect(
      emptyTrashResultMessage({ deleted: 2, total: 2, complete: true }),
    ).toContain("later was not included");
    expect(
      emptyTrashResultMessage({ deleted: 1, total: 2, complete: false }),
    ).toContain("could not be confirmed");
  });
});
