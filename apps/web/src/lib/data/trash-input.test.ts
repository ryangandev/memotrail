import { describe, expect, it } from "vitest";
import {
  parseTrashItemInput,
  parseTrashPage,
  trashPageHref,
} from "./trash-input";

const itemId = "21000000-0000-4000-8000-000000000001";
const deletedAt = "2026-09-02T12:34:56.000Z";

describe("Trash route input", () => {
  it("defaults an absent page to one", () => {
    expect(parseTrashPage(undefined)).toBe(1);
    expect(parseTrashPage("")).toBe(1);
  });

  it("accepts safe pages and the first repeated value", () => {
    expect(parseTrashPage("2")).toBe(2);
    expect(parseTrashPage(["3", "4"])).toBe(3);
  });

  it("rejects pages outside the database contract", () => {
    expect(parseTrashPage("0")).toBeNull();
    expect(parseTrashPage("1.5")).toBeNull();
    expect(parseTrashPage("402")).toBeNull();
    expect(parseTrashPage("anything")).toBeNull();
  });

  it("builds stable pagination links", () => {
    expect(trashPageHref(1)).toBe("/trash");
    expect(trashPageHref(3)).toBe("/trash?page=3");
    expect(trashPageHref(0)).toBe("/trash");
  });
});

describe("Trash item input", () => {
  it("accepts revisioned Entry identities and refuses retired kinds", () => {
    expect(
      parseTrashItemInput({
        deletedAt,
        itemId,
        itemKind: "entry",
        revision: 2,
      }),
    ).toMatchObject({ success: true });
    for (const itemKind of ["person", "place", "collection"]) {
      expect(
        parseTrashItemInput({
          deletedAt,
          itemId,
          itemKind,
          revision: 1,
        }).success,
      ).toBe(false);
    }
  });

  it("accepts a revision-free attachment identity", () => {
    expect(
      parseTrashItemInput({
        deletedAt,
        itemId,
        itemKind: "attachment",
        revision: null,
      }),
    ).toEqual({
      data: { deletedAt, itemId, itemKind: "attachment", revision: null },
      success: true,
    });
  });

  it("rejects invalid kinds, identifiers, and timestamps", () => {
    expect(
      parseTrashItemInput({ deletedAt, itemId, itemKind: "note", revision: 1 }),
    ).toMatchObject({ success: false });
    expect(
      parseTrashItemInput({
        deletedAt,
        itemId: "not-a-uuid",
        itemKind: "entry",
        revision: 1,
      }),
    ).toMatchObject({ success: false });
    expect(
      parseTrashItemInput({
        deletedAt: "tomorrow",
        itemId,
        itemKind: "entry",
        revision: 1,
      }),
    ).toMatchObject({ success: false });
  });

  it("enforces revision semantics for each item kind", () => {
    expect(
      parseTrashItemInput({
        deletedAt,
        itemId,
        itemKind: "entry",
        revision: null,
      }),
    ).toMatchObject({ success: false });
    expect(
      parseTrashItemInput({
        deletedAt,
        itemId,
        itemKind: "attachment",
        revision: 1,
      }),
    ).toMatchObject({ success: false });
  });
});
