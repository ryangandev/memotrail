import { beforeEach, expect, it, vi } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
vi.mock("server-only", () => ({}));
vi.mock("./server", () => ({
  AIError: class extends Error {
    constructor(
      public code: string,
      public status: number,
      message: string,
    ) {
      super(message);
    }
  },
  generateAI: vi.fn(),
  aiProviderConfigured: vi.fn(),
}));
import { AIError, generateAI, aiProviderConfigured } from "./server";
import {
  explorationWorkspace,
  saveExploration,
  sendExploration,
} from "./exploration-server";
const generate = vi.mocked(generateAI),
  configured = vi.mocked(aiProviderConfigured);
const rpc = vi.fn(),
  adminRPC = vi.fn();
const chain = {
  select: vi.fn().mockReturnThis(),
  eq: vi.fn().mockReturnThis(),
  in: vi.fn().mockReturnThis(),
  limit: vi.fn().mockResolvedValue({ data: [], error: null }),
};
const client = { rpc, from: vi.fn(() => chain) } as unknown as SupabaseClient;
const admin = { rpc: adminRPC } as unknown as SupabaseClient;
const turn = {
  id: "request",
  sequence: 1,
  question: "Why?",
  source_revision: 1,
  source_snapshot: { body: "Original writing" },
};
const input = {
  action: "send" as const,
  entryID: "entry",
  requestID: "request",
  question: "Why?",
  sourceRevision: 1,
};
const workspace = {
  source: { id: "entry", body: "Original writing", revision: 1 },
  turns: [],
  total_count: 0,
};
beforeEach(() => {
  vi.clearAllMocks();
  configured.mockReturnValue(true);
  rpc.mockResolvedValue({ data: workspace, error: null });
  adminRPC.mockImplementation(async (name) => ({
    data: name === "claim_exploration_turn" ? { claimed: true, turn } : true,
    error: null,
  }));
  generate.mockResolvedValue({
    text: '{"answer":"An interpretation"}',
    model: "claude-haiku-4-5-20251001",
    usageID: "usage",
  });
});
it("generates once using a claimed source snapshot then persists the separate answer", async () => {
  await sendExploration(client, "owner", input, admin);
  expect(generate).toHaveBeenCalledTimes(1);
  expect(generate).toHaveBeenCalledWith(
    "owner",
    "explore",
    expect.any(String),
    expect.stringContaining("Original writing"),
    1600,
    expect.any(Object),
  );
  expect(adminRPC).toHaveBeenLastCalledWith(
    "finish_exploration_turn",
    expect.objectContaining({
      p_answer: "An interpretation",
      p_request_id: "request",
      p_error_code: null,
    }),
  );
  expect(client.from).toHaveBeenCalledWith("entry_links");
});
it("replays an existing claim without another paid generation", async () => {
  adminRPC.mockResolvedValue({ data: { claimed: false, turn }, error: null });
  await sendExploration(client, "owner", input, admin);
  expect(generate).not.toHaveBeenCalled();
  expect(adminRPC).toHaveBeenCalledTimes(1);
});
it.each([
  "entry_changed",
  "exploration_busy",
  "ai_disabled",
  "request_id_conflict",
])("does not generate when claim rejects %s", async (message) => {
  adminRPC.mockResolvedValue({ data: null, error: { message } });
  await expect(
    sendExploration(client, "owner", input, admin),
  ).rejects.toMatchObject({ code: message });
  expect(generate).not.toHaveBeenCalled();
});
it("persists invalid output as failed without automatic retry", async () => {
  generate.mockResolvedValue({
    text: '{"answer":""}',
    model: "test",
    usageID: "usage",
  });
  await expect(
    sendExploration(client, "owner", input, admin),
  ).rejects.toMatchObject({ code: "invalid_answer" });
  expect(adminRPC).toHaveBeenLastCalledWith(
    "finish_exploration_turn",
    expect.objectContaining({ p_answer: null, p_error_code: "invalid_answer" }),
  );
  expect(generate).toHaveBeenCalledTimes(1);
});
it("records budget refusal as a failed attempt", async () => {
  generate.mockRejectedValue(
    new AIError("budget_exceeded", 429, "Budget reached"),
  );
  await expect(
    sendExploration(client, "owner", input, admin),
  ).rejects.toMatchObject({ status: 429 });
  expect(adminRPC).toHaveBeenLastCalledWith(
    "finish_exploration_turn",
    expect.objectContaining({ p_error_code: "budget_exceeded" }),
  );
});
it("does not report success when completion persistence is unconfirmed", async () => {
  adminRPC.mockImplementation(async (name) => ({
    data: name === "claim_exploration_turn" ? { claimed: true, turn } : false,
    error: null,
  }));
  await expect(
    sendExploration(client, "owner", input, admin),
  ).rejects.toMatchObject({ code: "completion_unconfirmed" });
});
it("keeps workspace and manual save available with the provider disabled", async () => {
  configured.mockReturnValue(false);
  await expect(explorationWorkspace(client, "entry")).resolves.toMatchObject(
    workspace,
  );
  rpc.mockResolvedValue({
    data: { entry_id: "saved", created: true },
    error: null,
  });
  await expect(
    saveExploration(client, {
      action: "save",
      requestID: "save",
      turnID: "request",
      title: "Edited",
      body: "My conclusion",
    }),
  ).resolves.toEqual({ entry_id: "saved", created: true });
  expect(generate).not.toHaveBeenCalled();
  await expect(
    sendExploration(client, "owner", input, admin),
  ).rejects.toMatchObject({ code: "provider_unavailable" });
  expect(adminRPC).not.toHaveBeenCalled();
});
it("does not expose an unavailable source", async () => {
  rpc.mockResolvedValue({ data: null, error: null });
  await expect(
    explorationWorkspace(client, "other-owner-entry"),
  ).rejects.toMatchObject({ status: 404 });
  expect(client.from).not.toHaveBeenCalled();
});
