import { describe, it, expect } from "vitest";
import { validTagInput, type TagInput } from "./organization";
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
