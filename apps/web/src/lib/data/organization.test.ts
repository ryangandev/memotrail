import { describe, it, expect } from "vitest";
import {
  existingTagName,
  tagNamesIncludingDraft,
  validTagInput,
  validTagName,
  type TagInput,
} from "./organization";
import { tagOptionsByUse } from "./tag-options";
describe("Tag settings", () => {
  const input: TagInput = { name: " 学习 ", id: null, revision: null };
  it("accepts bilingual tags", () => {
    expect(validTagInput(input)).toBe(true);
  });
  it("bounds names and identity", () => {
    expect(validTagInput({ ...input, name: "x".repeat(80) })).toBe(true);
    for (const change of [
      { name: " " },
      { name: "x".repeat(81) },
      { revision: 1 },
      { id: "x", revision: 1 },
    ])
      expect(validTagInput({ ...input, ...change })).toBe(false);
    expect(
      validTagInput({
        ...input,
        id: "96000000-0000-4000-8000-000000000002",
        revision: 2,
      }),
    ).toBe(true);
  });
});

describe("Tag names", () => {
  it("accepts every length a tag can be saved with, counted in characters", () => {
    expect(validTagName(` ${"x".repeat(80)} `)).toBe("x".repeat(80));
    expect(validTagName("学".repeat(80))).toBe("学".repeat(80));
    expect(validTagName("😀".repeat(80))).toBe("😀".repeat(80));
    expect(validTagName("x".repeat(81))).toBeNull();
    expect(validTagName("  ")).toBeNull();
  });
});

describe("Tag choices", () => {
  const options = ["Travel", "family"];
  it("reuses an existing tag that differs only by case", () => {
    expect(existingTagName(" travel ", options)).toBe("Travel");
    expect(existingTagName("FAMILY", options)).toBe("family");
    expect(existingTagName(" Seattle ", options)).toBe("Seattle");
  });
  it("saves a typed tag once, as the existing tag", () => {
    expect(tagNamesIncludingDraft(["family"], " travel", options)).toEqual([
      "family",
      "Travel",
    ]);
    expect(tagNamesIncludingDraft(["Travel"], "TRAVEL", options)).toEqual([
      "Travel",
    ]);
    expect(tagNamesIncludingDraft(["Travel"], "  ", options)).toEqual([
      "Travel",
    ]);
  });
  it("orders tags by how many Entries use them, then by name", () => {
    expect(
      tagOptionsByUse([
        { name: "travel", entry_tags: [{ count: 1 }] },
        { name: "Books", entry_tags: [{ count: 1 }] },
        { name: "family", entry_tags: [{ count: 4 }] },
        { name: "unused", entry_tags: [] },
      ]),
    ).toEqual(["family", "Books", "travel", "unused"]);
  });
});
