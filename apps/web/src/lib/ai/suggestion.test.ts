import { describe, it, expect } from "vitest";
import { parseEntryAISuggestions, mergeAISuggestionNames } from "./suggestion";
const valid = {
  title: "牙套的原理",
  entryType: "standard",
  collections: ["Learning"],
  tags: ["牙齿"],
  dateText: null,
  rationale: "记录刚学到的知识。",
  confidence: 0.9,
};
describe("Untrusted AI suggestions", () => {
  it("preserves Chinese content and optional dates", () =>
    expect(parseEntryAISuggestions(valid)).toEqual(valid));
  it("rejects invented Entry Types and invalid confidence", () => {
    expect(
      parseEntryAISuggestions({ ...valid, entryType: "learning" }),
    ).toBeNull();
    expect(parseEntryAISuggestions({ ...valid, confidence: 2 })).toBeNull();
    expect(parseEntryAISuggestions({ ...valid, confidence: NaN })).toBeNull();
  });
  it("rejects oversized names, prose, and malformed arrays", () => {
    expect(
      parseEntryAISuggestions({ ...valid, tags: ["x".repeat(61)] }),
    ).toBeNull();
    expect(
      parseEntryAISuggestions({ ...valid, collections: "Learning" }),
    ).toBeNull();
    expect(
      parseEntryAISuggestions({ ...valid, rationale: "x".repeat(1001) }),
    ).toBeNull();
  });
  it("does not accept actions or arbitrary fields from model output", () => {
    expect(
      parseEntryAISuggestions({
        ...valid,
        action: "delete",
        owner_id: "other",
      }),
    ).toEqual(valid);
  });
  it("merges suggestions without removing manual names or crossing limits", () => {
    expect(
      mergeAISuggestionNames(["My Learning"], ["my learning", "Science"], 2),
    ).toEqual(["My Learning", "Science"]);
    expect(mergeAISuggestionNames(["A", "B"], ["C"], 2)).toEqual(["A", "B"]);
  });
});
