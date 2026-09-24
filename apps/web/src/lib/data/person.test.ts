import { describe, expect, it } from "vitest";
import { parsePersonInput, personEntryTitle } from "./person";
import { parseTrashItemInput } from "./trash-input";

const input = {
  id: null,
  revision: null,
  name: " Friend ",
  relationshipLabel: " Mentor ",
  notes: " Notes ",
  entryIds: [],
};
describe("People contract", () => {
  it("normalizes context and deduplicates Entry identities", () => {
    const id = "ABCDEF01-0000-4000-8000-000000000001";
    expect(
      parsePersonInput({ ...input, entryIds: [id, id.toLowerCase()] }),
    ).toEqual({
      ...input,
      name: "Friend",
      relationshipLabel: "Mentor",
      notes: "Notes",
      entryIds: [id.toLowerCase()],
    });
  });
  it("rejects invalid identities, excessive context, and bad links", () => {
    for (const change of [
      { name: " " },
      { name: "x".repeat(201) },
      { notes: "x".repeat(10001) },
      { id: "bad" },
      { revision: 2 },
      { entryIds: [null] },
    ]) {
      expect(parsePersonInput({ ...input, ...change })).toBeNull();
    }
  });
  it("requires a revision for existing people", () => {
    const id = "abcdef01-0000-4000-8000-000000000001";
    expect(parsePersonInput({ ...input, id })).toBeNull();
    expect(parsePersonInput({ ...input, id, revision: 1 })).not.toBeNull();
  });
  it("presents a body-only Entry and accepts versioned People in shared Trash", () => {
    expect(
      personEntryTitle({
        id: "test",
        title: " ",
        body: "A meaningful walk",
        item_kind: "entry",
        item_subtype: "note",
      }),
    ).toBe("A meaningful walk");
    expect(
      parseTrashItemInput({
        itemKind: "person",
        itemId: "abcdef01-0000-4000-8000-000000000001",
        revision: 2,
        deletedAt: "2026-09-12T12:00:00Z",
      }).success,
    ).toBe(true);
  });
});
