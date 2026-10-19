import { afterEach, beforeEach, expect, it, vi } from "vitest";
vi.mock("server-only", () => ({}));
// Exercise the retained request logic independently of which features the product offers.
vi.mock("./availability", () => ({
  AI_PAUSED_MESSAGE: "paused",
  aiFeatureAvailable: () => true,
}));
const rpc = vi.hoisted(() => vi.fn());
vi.mock("@supabase/supabase-js", () => ({ createClient: () => ({ rpc }) }));
vi.mock("@/lib/supabase/server", () => ({ createClient: vi.fn() }));
vi.mock("@/lib/supabase/config", () => ({
  requireSupabasePublicConfig: () => ({ url: "http://local.test" }),
}));
import { AIError, aiMonthlyBudgets, generateAI, requestAI } from "./server";
import { AI_MODEL, REVIEW_MODEL } from "./contracts";
import { AI_PHOTO_RESERVE, type AIImage } from "./image-input";
import { setAIProviderForTests } from "./provider";
import {
  completed,
  cutOff,
  fakeProvider,
  interrupted,
  outage,
  refusal,
  rejected,
} from "./fake-provider";

const photo: AIImage = {
  mediaType: "image/webp",
  data: Buffer.from("RIFF0000WEBPtest").toString("base64"),
};
beforeEach(() => {
  vi.clearAllMocks();
  vi.stubEnv("AI_PROVIDER", "anthropic");
  vi.stubEnv("AI_API_KEY", "synthetic-test-key");
  vi.stubEnv("SUPABASE_SECRET_KEY", "synthetic-test-key");
  vi.stubEnv("AI_CHAT_MODEL", "");
  vi.stubEnv("AI_REVIEW_MODEL", "");
  vi.stubEnv("AI_API_BASE_URL", "");
  vi.stubEnv("AI_MONTHLY_BUDGET_USD", "0.1");
  vi.stubEnv("AI_USER_MONTHLY_BUDGET_USD", "");
  rpc.mockResolvedValue({ data: "usage", error: null });
});
afterEach(() => {
  setAIProviderForTests(null);
  vi.unstubAllEnvs();
});

const finishCall = () =>
  rpc.mock.calls.find(([name]) => name === "finish_ai_usage")?.[1];

it("reserves image input conservatively at the paused model's prices and sends inline previews", async () => {
  const { provider, requests } = fakeProvider(completed("OK"));
  setAIProviderForTests(provider);
  await generateAI(
    "owner",
    "photo_analysis",
    "system",
    "prompt",
    10,
    undefined,
    [photo],
  );
  expect(rpc).toHaveBeenCalledWith(
    "reserve_ai_usage",
    expect.objectContaining({
      p_feature: "photo_analysis",
      p_model: AI_MODEL,
      p_reserved_micros: 12 + 4096 + 50 + AI_PHOTO_RESERVE,
    }),
  );
  expect(requests[0].model).toBe(AI_MODEL);
  expect(requests[0].effort).toBeUndefined();
  expect(requests[0].images).toEqual([
    {
      type: "image",
      source: { type: "base64", media_type: "image/webp", data: photo.data },
    },
  ]);
  expect(finishCall()).toMatchObject({
    p_status: "completed",
    p_input_tokens: 1000,
    p_output_tokens: 200,
  });
});

it("reserves reviews at the review model's prices against both monthly budgets", async () => {
  const { provider, requests } = fakeProvider(completed({ ok: true }));
  setAIProviderForTests(provider);
  const result = await requestAI({
    ownerID: "owner",
    feature: "review",
    system: "system",
    input: "prompt",
    maxTokens: 4000,
    schema: { type: "object" },
    effort: "medium",
  });
  const schemaBytes = JSON.stringify({ type: "object" }).length;
  expect(rpc).toHaveBeenCalledWith("reserve_ai_usage", {
    p_owner_id: "owner",
    p_feature: "review",
    p_model: REVIEW_MODEL,
    p_reserved_micros: (12 + schemaBytes) * 2 + 4000 * 10 + 4096 * 2,
    p_global_budget_micros: 100_000,
    p_user_budget_micros: 3_000_000,
  });
  expect(requests[0]).toMatchObject({
    model: REVIEW_MODEL,
    effort: "medium",
    maxTokens: 4000,
    timeoutMs: 240_000,
  });
  expect(result).toMatchObject({ model: REVIEW_MODEL, inputTokens: 1000, outputTokens: 200 });
});

it("reads both monthly budgets from the environment and refuses nonsense", () => {
  vi.stubEnv("AI_MONTHLY_BUDGET_USD", "25");
  vi.stubEnv("AI_USER_MONTHLY_BUDGET_USD", "1.5");
  expect(aiMonthlyBudgets()).toEqual({ server: 25_000_000, user: 1_500_000 });
  for (const bad of ["0", "-1", "abc", "1001"]) {
    vi.stubEnv("AI_MONTHLY_BUDGET_USD", bad);
    expect(aiMonthlyBudgets()).toBeNull();
  }
  vi.stubEnv("AI_MONTHLY_BUDGET_USD", "25");
  vi.stubEnv("AI_USER_MONTHLY_BUDGET_USD", "101");
  expect(aiMonthlyBudgets()).toBeNull();
});

it("uses the monthly defaults when nothing is configured", () => {
  vi.stubEnv("AI_MONTHLY_BUDGET_USD", undefined);
  vi.stubEnv("AI_USER_MONTHLY_BUDGET_USD", undefined);
  expect(aiMonthlyBudgets()).toEqual({ server: 25_000_000, user: 3_000_000 });
});

it("enforces each feature's prompt and answer limits before reserving anything", async () => {
  const { provider, requests } = fakeProvider();
  setAIProviderForTests(provider);
  const big = (bytes: number) => "a".repeat(bytes);
  const refused = (options: Parameters<typeof requestAI>[0]) =>
    expect(requestAI(options)).rejects.toMatchObject({ code: "request_too_large" });
  await refused({ ownerID: "o", feature: "classification", system: "", input: big(64_001) });
  await refused({ ownerID: "o", feature: "classification", system: "", input: "x", maxTokens: 2049 });
  await refused({ ownerID: "o", feature: "review", system: "", input: big(800_001), maxTokens: 100 });
  await refused({ ownerID: "o", feature: "review", system: "", input: "x", maxTokens: 16_001 });
  await refused({ ownerID: "o", feature: "chapter_suggestion", system: "", input: big(160_001), maxTokens: 100 });
  await refused({ ownerID: "o", feature: "chapter_suggestion", system: "", input: "x", maxTokens: 6_001 });
  await refused({ ownerID: "o", feature: "review", system: "", input: "x", maxTokens: 0 });
  await refused({ ownerID: "o", feature: "review", system: "", input: "x", maxTokens: 1.5 });
  await refused({ ownerID: "o", feature: "review", system: "", input: "x", model: "claude-unpriced" });
  expect(rpc).not.toHaveBeenCalled();
  expect(requests).toHaveLength(0);
});

it("keeps the largest allowed review under the two dollar reservation bound", async () => {
  const { provider } = fakeProvider(completed("OK"));
  setAIProviderForTests(provider);
  await requestAI({
    ownerID: "owner",
    feature: "review",
    system: "",
    input: "a".repeat(800_000),
    maxTokens: 16_000,
  });
  const reserved = rpc.mock.calls[0][1].p_reserved_micros;
  expect(reserved).toBe(800_000 * 2 + 16_000 * 10 + 4096 * 2);
  expect(reserved).toBeLessThanOrEqual(2_000_000);
});

it("requires the independently authorized photo feature before sending image data", async () => {
  const { provider, requests } = fakeProvider(completed("OK"));
  setAIProviderForTests(provider);
  await expect(
    generateAI("owner", "classification", "system", "prompt", 10, undefined, [photo]),
  ).rejects.toMatchObject({ code: "invalid_images" });
  expect(rpc).not.toHaveBeenCalled();
  expect(requests).toHaveLength(0);
});

it("does not send anything when the atomic permission and budget reservation refuses", async () => {
  const { provider, requests } = fakeProvider(completed("OK"));
  setAIProviderForTests(provider);
  for (const [message, code, status] of [
    ["ai_disabled", "ai_disabled", 403],
    ["ai_budget_exceeded", "budget_exceeded", 429],
    ["ai_rate_limit", "rate_limit", 429],
    ["something_else", "usage_unavailable", 503],
  ] as const) {
    rpc.mockResolvedValueOnce({ data: null, error: { message } });
    await expect(
      requestAI({ ownerID: "owner", feature: "review", system: "s", input: "p" }),
    ).rejects.toMatchObject({ code, status });
  }
  expect(requests).toHaveLength(0);
});

it("rejects malformed images before reserving or sending", async () => {
  const { provider, requests } = fakeProvider(completed("OK"));
  setAIProviderForTests(provider);
  await expect(
    generateAI("owner", "photo_analysis", "system", "prompt", 10, undefined, [
      { ...photo, data: "https://example.com" },
    ]),
  ).rejects.toMatchObject({ code: "invalid_images" });
  expect(rpc).not.toHaveBeenCalled();
  expect(requests).toHaveLength(0);
});

it("charges a refusal as billed and reports it", async () => {
  setAIProviderForTests(fakeProvider(refusal()).provider);
  await expect(
    requestAI({ ownerID: "owner", feature: "review", system: "s", input: "p" }),
  ).rejects.toMatchObject({ code: "review_declined", status: 502 });
  expect(finishCall()).toMatchObject({
    p_status: "completed",
    p_input_tokens: 1000,
    p_error_code: "review_declined",
  });
});

it("charges a cut-off answer as billed and reports it", async () => {
  setAIProviderForTests(fakeProvider(cutOff()).provider);
  await expect(
    requestAI({ ownerID: "owner", feature: "review", system: "s", input: "p" }),
  ).rejects.toMatchObject({ code: "incomplete_generation" });
  expect(finishCall()).toMatchObject({ p_status: "completed", p_error_code: "incomplete_generation" });
});

it("keeps an interrupted request's reservation charged and a rejected one free", async () => {
  setAIProviderForTests(fakeProvider(interrupted(), outage(), rejected()).provider);
  const call = () =>
    requestAI({ ownerID: "owner", feature: "review", system: "s", input: "p" });
  await expect(call()).rejects.toMatchObject({ code: "provider_interrupted" });
  expect(finishCall()).toMatchObject({ p_status: "uncertain", p_input_tokens: null });
  rpc.mockClear();
  await expect(call()).rejects.toMatchObject({ code: "provider_error" });
  expect(finishCall()).toMatchObject({ p_status: "uncertain" });
  rpc.mockClear();
  await expect(call()).rejects.toMatchObject({ code: "provider_error" });
  expect(finishCall()).toMatchObject({ p_status: "failed", p_error_code: "provider_error" });
});

it("treats an unexpected provider exception as interrupted and unknown", async () => {
  setAIProviderForTests({
    generate: async () => {
      throw new Error("socket hang up");
    },
  });
  await expect(
    requestAI({ ownerID: "owner", feature: "review", system: "s", input: "p" }),
  ).rejects.toBeInstanceOf(AIError);
  expect(finishCall()).toMatchObject({ p_status: "uncertain", p_error_code: "provider_interrupted" });
});

it("needs a configured provider, review model, and address", async () => {
  const call = () =>
    requestAI({ ownerID: "owner", feature: "review", system: "s", input: "p" });
  vi.stubEnv("AI_REVIEW_MODEL", "claude-opus-5-5");
  await expect(call()).rejects.toMatchObject({ code: "provider_unavailable" });
  vi.stubEnv("AI_REVIEW_MODEL", REVIEW_MODEL);
  vi.stubEnv("AI_API_BASE_URL", "http://example.com");
  await expect(call()).rejects.toMatchObject({ code: "provider_unavailable" });
  vi.stubEnv("AI_API_BASE_URL", "");
  vi.stubEnv("AI_PROVIDER", "other");
  await expect(call()).rejects.toMatchObject({ code: "provider_unavailable" });
  expect(rpc).not.toHaveBeenCalled();
});
