import { describe, it, expect } from "vitest";
import { parseGoalConversionInput } from "./goal-record-input";
const input = {
  id: "9ee35d43-af21-41c4-9bdb-2864b99622f0",
  revision: 3,
  title: " 学习 ",
  horizon: "someday",
  status: "considering",
  targetDate: null,
};
describe("Goal conversion input", () => {
  it("keeps identity and only exposes explicit conversion fields", () => {
    expect(
      parseGoalConversionInput({
        ...input,
        body: "Do not overwrite",
        collectionNames: ["Ignore"],
      }),
    ).toEqual({ success: true, data: { ...input, title: "学习" } });
  });
  it("rejects invalid versions, titles, states and calendar dates", () => {
    for (const patch of [
      { id: null },
      { id: "bad" },
      { revision: 0 },
      { revision: 1.5 },
      { title: " " },
      { status: "bad" },
      { horizon: null },
      { targetDate: "2026-02-30" },
    ])
      expect(parseGoalConversionInput({ ...input, ...patch }).success).toBe(
        false,
      );
  });
});
