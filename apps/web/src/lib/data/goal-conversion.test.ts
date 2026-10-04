import { describe, it, expect } from "vitest";
import { parseGoalExtractionInput } from "./goal-record-input";
const input = {
  goalId: "50000000-0000-4000-8000-000000000001",
  sourceId: "9ee35d43-af21-41c4-9bdb-2864b99622f0",
  sourceRevision: 3,
  title: " 学习 ",
  targetDate: null,
};
describe("Goal extraction input", () => {
  it("keeps source and target identity and only exposes title and target", () => {
    expect(
      parseGoalExtractionInput({
        ...input,
        body: "Do not overwrite",
        horizon: "someday",
        status: "achieved",
      }),
    ).toEqual({ success: true, data: { ...input, title: "学习" } });
  });
  it("rejects invalid versions, titles and calendar dates", () => {
    for (const patch of [
      { goalId: null },
      { goalId: "bad" },
      { sourceId: "bad" },
      { sourceRevision: 0 },
      { sourceRevision: 1.5 },
      { title: " " },
      { targetDate: "2026-02-30" },
    ])
      expect(parseGoalExtractionInput({ ...input, ...patch }).success).toBe(
        false,
      );
  });
});
