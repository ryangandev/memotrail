import { expect, it } from "vitest";
import {
  explorationPrompt,
  parseExplorationAnswer,
  parseExplorationRequest,
  type ExplorationTurn,
  type ExplorationWorkspace,
} from "./exploration";
const id = "11111111-1111-4111-8111-111111111111";
const send = {
  action: "send",
  entryID: id,
  requestID: id,
  question: " 为什么学习？ ",
  sourceRevision: 1,
};
it("validates exact action shapes and trims human writing", () => {
  expect(parseExplorationRequest(send)).toEqual({
    ...send,
    question: "为什么学习？",
  });
  expect(
    parseExplorationRequest({
      action: "workspace",
      entryID: id,
      beforeSequence: 4,
    }),
  ).not.toBeNull();
  expect(
    parseExplorationRequest({
      action: "save",
      requestID: id,
      turnID: id,
      title: " ",
      body: " 结论 ",
    }),
  ).toMatchObject({ title: "", body: "结论" });
});
it.each([
  null,
  [],
  {},
  { ...send, action: "delete" },
  { ...send, ownerID: id },
  { ...send, entryID: "bad" },
  { ...send, sourceRevision: 0 },
  { ...send, sourceRevision: 1.5 },
  { ...send, question: " " },
  { ...send, question: "🙂".repeat(1001) },
  { action: "workspace", entryID: id, beforeSequence: 0 },
  {
    action: "workspace",
    entryID: id,
    beforeSequence: Number.MAX_SAFE_INTEGER + 1,
  },
  {
    action: "save",
    requestID: id,
    turnID: id,
    title: "x".repeat(201),
    body: "text",
  },
  {
    action: "save",
    requestID: id,
    turnID: id,
    title: "",
    body: "x".repeat(50001),
  },
])("rejects invalid or oversized requests: %j", (input) => {
  expect(parseExplorationRequest(input)).toBeNull();
});
it.each([
  "{}",
  "null",
  "[]",
  '{"answer":" "}',
  '{"answer":"ok","extra":true}',
  "not JSON",
  JSON.stringify({ answer: "x".repeat(12001) }),
])("rejects unsafe response shape %s", (input) => {
  expect(parseExplorationAnswer(input)).toBeNull();
});
it("keeps valid answers as plain text", () => {
  expect(parseExplorationAnswer('{"answer":"  一个新视角。  "}')).toBe(
    "一个新视角。",
  );
});
it("bounds escaped Unicode source and only eight prior completed turns", () => {
  const turn: ExplorationTurn = {
    id,
    entry_id: id,
    sequence: 40,
    question: "\u0001".repeat(2000),
    source_revision: 2,
    source_snapshot: {
      title: "🙂".repeat(1000),
      body: "\u0001🙂".repeat(10000),
      body_truncated: true,
    },
    status: "generating",
    answer: null,
    model: null,
    error_code: null,
    created_at: "",
    saved_entries: [],
  };
  const turns = Array.from({ length: 20 }, (_, index) => ({
    ...turn,
    sequence: index,
    status: "completed" as const,
    question: `Q${index} ` + "\u0001".repeat(2000),
    answer: "🙂".repeat(12000),
  }));
  const workspace: ExplorationWorkspace = {
    source: {
      id,
      title: "NEW TITLE NOT USED",
      body: "NEW BODY NOT USED",
      revision: 99,
    },
    turns: [...turns, turn],
    total_count: 40,
    links: [],
    linksTruncated: false,
  };
  const prompt = explorationPrompt(turn, workspace);
  expect(Buffer.byteLength(prompt)).toBeLessThan(62500);
  const context = JSON.parse(prompt);
  expect(context.recentTurns).toHaveLength(8);
  expect(context.recentTurns[0].question.text).toContain("Q12");
  expect(context.source.revision).toBe(2);
  expect(context.source.excerptOnly).toBe(true);
  expect(context.olderTurnsOmitted).toBe(true);
  expect(prompt).not.toContain("NEW BODY");
  expect(prompt).not.toContain("\\ud83d");
});
