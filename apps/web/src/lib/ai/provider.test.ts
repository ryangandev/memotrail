import { createServer, type IncomingMessage, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { afterAll, afterEach, beforeAll, beforeEach, expect, it, vi } from "vitest";
vi.mock("server-only", () => ({}));
import { AIProviderFailure, anthropicProvider, readAIBaseURL } from "./provider";

type Handler = (request: IncomingMessage, body: string) => {
  status?: number;
  events?: Array<[string, unknown]>;
  error?: { type: string; message: string };
};
let server: Server;
let handler: Handler;
let seen: Array<{ headers: IncomingMessage["headers"]; body: Record<string, unknown> }>;

function message(blocks: Array<Record<string, unknown>>, stop = "end_turn") {
  const events: Array<[string, unknown]> = [
    [
      "message_start",
      {
        type: "message_start",
        message: {
          id: "msg_test",
          type: "message",
          role: "assistant",
          model: "claude-sonnet-5-5",
          content: [],
          stop_reason: null,
          stop_sequence: null,
          usage: { input_tokens: 120, output_tokens: 1 },
        },
      },
    ],
  ];
  blocks.forEach((block, index) => {
    const isThinking = block.type === "thinking";
    events.push([
      "content_block_start",
      {
        type: "content_block_start",
        index,
        content_block: isThinking
          ? { type: "thinking", thinking: "", signature: "" }
          : { type: "text", text: "" },
      },
    ]);
    events.push([
      "content_block_delta",
      {
        type: "content_block_delta",
        index,
        delta: isThinking
          ? { type: "thinking_delta", thinking: block.text }
          : { type: "text_delta", text: block.text },
      },
    ]);
    events.push(["content_block_stop", { type: "content_block_stop", index }]);
  });
  events.push([
    "message_delta",
    {
      type: "message_delta",
      delta: { stop_reason: stop, stop_sequence: null },
      usage: { output_tokens: 42 },
    },
  ]);
  events.push(["message_stop", { type: "message_stop" }]);
  return events;
}

beforeAll(async () => {
  server = createServer((request, response) => {
    const chunks: Buffer[] = [];
    request.on("data", (chunk) => chunks.push(chunk));
    request.on("end", () => {
      const body = Buffer.concat(chunks).toString("utf8");
      seen.push({ headers: request.headers, body: JSON.parse(body) });
      const answer = handler(request, body);
      if (answer.error) {
        response.writeHead(answer.status ?? 400, { "content-type": "application/json" });
        response.end(JSON.stringify({ type: "error", error: answer.error }));
        return;
      }
      response.writeHead(200, { "content-type": "text/event-stream" });
      for (const [event, data] of answer.events ?? [])
        response.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
      response.end();
    });
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
});
afterAll(() => new Promise<void>((resolve) => server.close(() => resolve())));
beforeEach(() => {
  seen = [];
  vi.stubEnv("AI_API_KEY", "synthetic-test-key");
  vi.stubEnv(
    "AI_API_BASE_URL",
    `http://127.0.0.1:${(server.address() as AddressInfo).port}`,
  );
});
afterEach(() => vi.unstubAllEnvs());

const request = {
  model: "claude-sonnet-5-5",
  system: "system",
  input: "input",
  maxTokens: 500,
  timeoutMs: 5_000,
};

it("sends one adaptive-thinking request with a JSON schema and reads text and usage", async () => {
  handler = () => ({
    events: message([
      { type: "thinking", text: "Private reasoning that is never kept." },
      { type: "text", text: '{"ok":' },
      { type: "text", text: "true}" },
    ]),
  });
  const result = await anthropicProvider().generate({
    ...request,
    effort: "medium",
    schema: { type: "object" },
  });
  expect(result).toEqual({
    text: '{"ok":\ntrue}',
    inputTokens: 120,
    outputTokens: 42,
    stopReason: "end_turn",
    model: "claude-sonnet-5-5",
  });
  expect(seen).toHaveLength(1);
  expect(seen[0].headers["x-api-key"]).toBe("synthetic-test-key");
  expect(seen[0].body).toMatchObject({
    model: "claude-sonnet-5-5",
    max_tokens: 500,
    system: "system",
    messages: [{ role: "user", content: "input" }],
    thinking: { type: "adaptive" },
    output_config: {
      effort: "medium",
      format: { type: "json_schema", schema: { type: "object" } },
    },
  });
  expect(JSON.stringify(seen[0].body)).not.toContain("fallbacks");
});

it("sends neither thinking nor effort unless an effort is asked for", async () => {
  handler = () => ({ events: message([{ type: "text", text: "OK" }]) });
  await anthropicProvider().generate(request);
  expect(seen[0].body).not.toHaveProperty("thinking");
  expect(seen[0].body).not.toHaveProperty("output_config");
});

it("reports refusal and cut-off stop reasons for the caller to handle", async () => {
  handler = () => ({ events: message([{ type: "text", text: "" }], "refusal") });
  await expect(anthropicProvider().generate(request)).resolves.toMatchObject({
    stopReason: "refusal",
  });
  handler = () => ({ events: message([{ type: "text", text: "{" }], "max_tokens") });
  await expect(anthropicProvider().generate(request)).resolves.toMatchObject({
    stopReason: "max_tokens",
  });
});

it.each([
  [401, "authentication_error", "provider_authentication", "failed"],
  [400, "invalid_request_error", "provider_error", "failed"],
  [404, "not_found_error", "provider_error", "failed"],
  [429, "rate_limit_error", "provider_error", "uncertain"],
  [500, "api_error", "provider_error", "uncertain"],
  [529, "overloaded_error", "provider_error", "uncertain"],
])("maps HTTP %i to %s and never retries", async (status, type, code, outcome) => {
  handler = () => ({ status, error: { type, message: "No." } });
  await expect(anthropicProvider().generate(request)).rejects.toMatchObject({
    code,
    outcome,
  });
  expect(seen).toHaveLength(1);
});

it("treats a request that outlives its timeout as interrupted and unknown", async () => {
  handler = () => ({ events: [] });
  const slow = createServer(() => undefined);
  await new Promise<void>((resolve) => slow.listen(0, "127.0.0.1", resolve));
  vi.stubEnv("AI_API_BASE_URL", `http://127.0.0.1:${(slow.address() as AddressInfo).port}`);
  try {
    const failure = await anthropicProvider()
      .generate({ ...request, timeoutMs: 150 })
      .catch((error) => error);
    expect(failure).toBeInstanceOf(AIProviderFailure);
    expect(failure).toMatchObject({ code: "provider_interrupted", outcome: "uncertain" });
  } finally {
    slow.closeAllConnections();
    await new Promise<void>((resolve) => slow.close(() => resolve()));
  }
});

it("sends photo blocks before the text for the paused photo feature", async () => {
  handler = () => ({ events: message([{ type: "text", text: "OK" }]) });
  await anthropicProvider().generate({
    ...request,
    images: [
      {
        type: "image",
        source: { type: "base64", media_type: "image/webp", data: "AAAA" },
      },
    ],
  });
  expect((seen[0].body.messages as Array<{ content: unknown[] }>)[0].content).toEqual([
    { type: "image", source: { type: "base64", media_type: "image/webp", data: "AAAA" } },
    { type: "text", text: "input" },
  ]);
});

it("fails closed without a key or with an unsafe address", async () => {
  vi.stubEnv("AI_API_KEY", "");
  await expect(anthropicProvider().generate(request)).rejects.toMatchObject({
    code: "provider_unavailable",
  });
  vi.stubEnv("AI_API_KEY", "synthetic-test-key");
  vi.stubEnv("AI_API_BASE_URL", "http://example.com");
  await expect(anthropicProvider().generate(request)).rejects.toMatchObject({
    code: "provider_unavailable",
  });
  expect(seen).toHaveLength(0);
});

it("accepts only HTTPS or loopback addresses", () => {
  expect(readAIBaseURL({})).toEqual({ ok: true, baseURL: undefined });
  expect(readAIBaseURL({ AI_API_BASE_URL: "https://proxy.example.com/v1/" })).toEqual({
    ok: true,
    baseURL: "https://proxy.example.com/v1",
  });
  expect(readAIBaseURL({ AI_API_BASE_URL: "http://127.0.0.1:4010" })).toEqual({
    ok: true,
    baseURL: "http://127.0.0.1:4010",
  });
  expect(readAIBaseURL({ AI_API_BASE_URL: "http://localhost:4010" }).ok).toBe(true);
  for (const bad of ["http://example.com", "ftp://example.com", "not a url", "http://127.0.0.1.evil.test"])
    expect(readAIBaseURL({ AI_API_BASE_URL: bad })).toEqual({ ok: false });
});
