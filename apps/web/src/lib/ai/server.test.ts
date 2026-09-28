import { afterEach, beforeEach, expect, it, vi } from "vitest";
vi.mock("server-only", () => ({}));
// Keep exercising the retained provider logic independently of the product pause.
vi.mock("./availability", () => ({ AI_CAPABILITIES_AVAILABLE: true }));
const rpc = vi.hoisted(() => vi.fn());
vi.mock("@supabase/supabase-js", () => ({ createClient: () => ({ rpc }) }));
vi.mock("@/lib/supabase/server", () => ({ createClient: vi.fn() }));
vi.mock("@/lib/supabase/config", () => ({
  requireSupabasePublicConfig: () => ({ url: "http://local.test" }),
}));
import { generateAI } from "./server";
import { AI_PHOTO_RESERVE, type AIImage } from "./image-input";
const fetchMock = vi.fn();
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
  vi.stubEnv("AI_TOTAL_BUDGET_USD", "0.1");
  vi.stubGlobal("fetch", fetchMock);
  rpc.mockResolvedValue({ data: "usage", error: null });
  fetchMock.mockResolvedValue({
    ok: true,
    json: async () => ({
      usage: { input_tokens: 100, output_tokens: 3 },
      content: [{ type: "text", text: "OK" }],
      stop_reason: "end_turn",
    }),
  });
});
afterEach(() => {
  vi.unstubAllGlobals();
  vi.unstubAllEnvs();
});
it("reserves image input conservatively and sends inline previews only to Anthropic", async () => {
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
      p_reserved_micros: 12 + 4096 + 50 + AI_PHOTO_RESERVE,
    }),
  );
  const [url, request] = fetchMock.mock.calls[0];
  expect(url).toBe("https://api.anthropic.com/v1/messages");
  expect(JSON.parse(request.body).messages[0].content).toEqual([
    {
      type: "image",
      source: { type: "base64", media_type: "image/webp", data: photo.data },
    },
    { type: "text", text: "prompt" },
  ]);
  expect(rpc).toHaveBeenCalledWith(
    "finish_ai_usage",
    expect.objectContaining({
      p_status: "completed",
      p_input_tokens: 100,
      p_output_tokens: 3,
    }),
  );
});
it("requires the independently authorized photo feature before sending image data", async () => {
  await expect(
    generateAI("owner", "classification", "system", "prompt", 10, undefined, [
      photo,
    ]),
  ).rejects.toMatchObject({ code: "invalid_images" });
  expect(rpc).not.toHaveBeenCalled();
  expect(fetchMock).not.toHaveBeenCalled();
});
it("does not send photos when the atomic permission/budget reservation refuses", async () => {
  rpc.mockResolvedValue({ data: null, error: { message: "ai_disabled" } });
  await expect(
    generateAI("owner", "photo_analysis", "system", "prompt", 10, undefined, [
      photo,
    ]),
  ).rejects.toMatchObject({ code: "ai_disabled" });
  expect(fetchMock).not.toHaveBeenCalled();
});
it("rejects malformed images before reserving or sending", async () => {
  await expect(
    generateAI("owner", "photo_analysis", "system", "prompt", 10, undefined, [
      { ...photo, data: "https://example.com" },
    ]),
  ).rejects.toMatchObject({ code: "invalid_images" });
  expect(rpc).not.toHaveBeenCalled();
  expect(fetchMock).not.toHaveBeenCalled();
});
