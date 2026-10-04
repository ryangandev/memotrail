import { describe, expect, it } from "vitest";
import {
  isGoalEntryIdentity,
  parseGoalAchievementInput,
  parseGoalEntryInput,
} from "./goal-record-input";

const goalId = "40000000-0000-4000-8000-000000000001";
const relatedId = "40000000-0000-4000-8000-000000000002";
const validGoal = {
  body: " Learn the landscape, then decide. ",
  horizon: "long_term",
  id: goalId,
  relatedEntryIds: [relatedId, relatedId.toUpperCase()],
  revision: 3,
  status: "active",
  tagNames: [" Travel ", "travel", "curious"],
  targetDate: "2030-06-15",
  title: " Learn to sail ",
};

describe("parseGoalEntryInput", () => {
  it("normalizes a complete Goal edit", () => {
    const parsed = parseGoalEntryInput(validGoal);

    expect(parsed.success).toBe(true);
    if (parsed.success) {
      expect(parsed.data).toMatchObject({
        body: "Learn the landscape, then decide.",
        relatedEntryIds: [relatedId],
        tagNames: ["Travel", "curious"],
        targetDate: "2030-06-15",
        title: "Learn to sail",
      });
    }
  });

  it("accepts a minimal new Goal without a target", () => {
    expect(
      parseGoalEntryInput({
        ...validGoal,
        body: "",
        id: null,
        relatedEntryIds: [],
        revision: null,
        tagNames: [],
        targetDate: null,
      }),
    ).toMatchObject({ success: true });
  });

  it("rejects invalid content, states, targets, and links", () => {
    expect(parseGoalEntryInput({ ...validGoal, title: " " })).toMatchObject({
      success: false,
    });
    expect(
      parseGoalEntryInput({ ...validGoal, horizon: "weekly" }),
    ).toMatchObject({ success: false });
    expect(
      parseGoalEntryInput({ ...validGoal, status: "overdue" }),
    ).toMatchObject({ success: false });
    expect(
      parseGoalEntryInput({ ...validGoal, targetDate: "2030-02-30" }),
    ).toMatchObject({ success: false });
    expect(
      parseGoalEntryInput({ ...validGoal, relatedEntryIds: ["not-a-uuid"] }),
    ).toMatchObject({ success: false });
  });

  it("requires matching create or edit identity", () => {
    expect(isGoalEntryIdentity(goalId, 2)).toBe(true);
    expect(isGoalEntryIdentity(goalId, null)).toBe(false);
    expect(isGoalEntryIdentity(null, null)).toBe(true);
  });
});

describe("parseGoalAchievementInput", () => {
  it("normalizes supplied First Time context", () => {
    const parsed = parseGoalAchievementInput({
      datePrecision: "day",
      id: goalId,
      occurredLabel: " First summer on the water ",
      occurredStart: "2030-06-15T12:00:00-07:00",
      occurredTimezone: " America/Los_Angeles ",
      revision: 3,
    });

    expect(parsed.success).toBe(true);
    if (parsed.success) {
      expect(parsed.data.occurredStart).toBe("2030-06-15T19:00:00.000Z");
      expect(parsed.data.occurredLabel).toBe("First summer on the water");
    }
  });

  it("rejects unsaved achievements and reversed ranges", () => {
    expect(
      parseGoalAchievementInput({
        datePrecision: "day",
        id: null,
        occurredLabel: null,
        occurredStart: "2030-06-15T19:00:00Z",
        occurredTimezone: "UTC",
        revision: null,
      }),
    ).toMatchObject({ success: false });
    expect(
      parseGoalAchievementInput({
        datePrecision: "range",
        id: goalId,
        occurredLabel: null,
        occurredStart: "2030-06-15T19:00:00Z",
        occurredEnd: "2030-06-14T19:00:00Z",
        occurredTimezone: "UTC",
        revision: 3,
      }),
    ).toMatchObject({ success: false });
  });
  it("accepts description-only ages, unknown dates and complete ranges", () => {
    const base = {
      id: goalId,
      revision: 3,
      occurredTimezone: "UTC",
      occurredStart: null,
    };
    expect(
      parseGoalAchievementInput({
        ...base,
        datePrecision: "age",
        occurredLabel: "17岁",
      }),
    ).toMatchObject({
      success: true,
      data: { occurredStart: null, occurredEnd: null },
    });
    expect(
      parseGoalAchievementInput({ ...base, datePrecision: "unknown" }),
    ).toMatchObject({ success: true, data: { occurredStart: null } });
    expect(
      parseGoalAchievementInput({ ...base, datePrecision: "age" }),
    ).toMatchObject({ success: false });
    expect(
      parseGoalAchievementInput({
        ...base,
        datePrecision: "range",
        occurredStart: "2030-06-15T19:00:00.123456Z",
        occurredEnd: "2030-06-16T19:00:00Z",
      }),
    ).toMatchObject({
      success: true,
      data: {
        occurredStart: "2030-06-15T19:00:00.123456Z",
        occurredEnd: "2030-06-16T19:00:00.000Z",
      },
    });
  });
});
