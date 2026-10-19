import "server-only";
import Anthropic from "@anthropic-ai/sdk";
import type { imageContent } from "./image-input";

/**
 * The only third-party language-model boundary. `lib/search` stays outside it.
 * Requests go through the official SDK, never retry on their own (an interrupted
 * outcome is unknown and may have been billed), and ask for no server-side fallbacks:
 * one model keeps the disclosure and the price accounting exact.
 */
export type AIProviderRequest = {
  model: string;
  system: string;
  input: string;
  images?: ReturnType<typeof imageContent>;
  maxTokens: number;
  schema?: Record<string, unknown>;
  /** When set, the model thinks adaptively at this effort. Models without adaptive thinking leave it unset. */
  effort?: "low" | "medium" | "high";
  timeoutMs: number;
};

export type AIProviderResult = {
  text: string;
  inputTokens: number;
  outputTokens: number;
  stopReason: string;
  model: string;
};

export interface AIProvider {
  generate(request: AIProviderRequest): Promise<AIProviderResult>;
}

/**
 * `failed` means the provider rejected the request and nothing was billed.
 * `uncertain` means the request may have been billed, so its reservation stays charged.
 */
export class AIProviderFailure extends Error {
  constructor(
    public code: string,
    public outcome: "failed" | "uncertain",
    message = code,
  ) {
    super(message);
  }
}

/** An address over HTTPS, or a loopback address for the fake provider used by tests. */
export function readAIBaseURL(
  env: Record<string, string | undefined> = process.env,
): { ok: true; baseURL: string | undefined } | { ok: false } {
  const raw = env.AI_API_BASE_URL?.trim();
  if (!raw) return { ok: true, baseURL: undefined };
  try {
    const url = new URL(raw);
    const loopback = ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname);
    if (url.protocol !== "https:" && !(url.protocol === "http:" && loopback))
      return { ok: false };
    return { ok: true, baseURL: url.origin + url.pathname.replace(/\/+$/, "") };
  } catch {
    return { ok: false };
  }
}

function failureFor(error: unknown) {
  if (error instanceof AIProviderFailure) return error;
  if (error instanceof Anthropic.APIUserAbortError)
    return new AIProviderFailure("provider_interrupted", "uncertain");
  if (error instanceof Anthropic.APIConnectionError)
    return new AIProviderFailure("provider_interrupted", "uncertain");
  if (error instanceof Anthropic.APIError) {
    const status = error.status;
    if (status === 401)
      return new AIProviderFailure("provider_authentication", "failed");
    if (typeof status !== "number")
      return new AIProviderFailure("provider_interrupted", "uncertain");
    if (status === 429 || status >= 500)
      return new AIProviderFailure("provider_error", "uncertain");
    return new AIProviderFailure("provider_error", "failed");
  }
  return new AIProviderFailure("provider_interrupted", "uncertain");
}

let cached: { key: string; client: Anthropic } | null = null;

function clientFor(apiKey: string, baseURL: string | undefined) {
  const key = `${apiKey}\n${baseURL ?? ""}`;
  if (cached?.key !== key) {
    cached = {
      key,
      client: new Anthropic({ apiKey, baseURL, maxRetries: 0 }),
    };
  }
  return cached.client;
}

export function anthropicProvider(): AIProvider {
  return {
    async generate(request) {
      const base = readAIBaseURL();
      const apiKey = process.env.AI_API_KEY?.trim();
      if (!base.ok || !apiKey)
        throw new AIProviderFailure("provider_unavailable", "failed");
      const client = clientFor(apiKey, base.baseURL);
      const outputConfig = {
        ...(request.effort ? { effort: request.effort } : {}),
        ...(request.schema
          ? {
              format: {
                type: "json_schema" as const,
                schema: request.schema,
              },
            }
          : {}),
      };
      let message: Anthropic.Messages.Message;
      try {
        // Streamed so a long answer never waits on one silent connection; only the final message is used.
        const stream = client.messages.stream(
          {
            model: request.model,
            max_tokens: request.maxTokens,
            system: request.system,
            messages: [
              {
                role: "user",
                content: request.images?.length
                  ? [
                      ...request.images,
                      { type: "text" as const, text: request.input },
                    ]
                  : request.input,
              },
            ],
            ...(request.effort
              ? { thinking: { type: "adaptive" as const } }
              : {}),
            ...(Object.keys(outputConfig).length
              ? { output_config: outputConfig }
              : {}),
          },
          {
            timeout: request.timeoutMs,
            signal: AbortSignal.timeout(request.timeoutMs),
          },
        );
        message = await stream.finalMessage();
      } catch (error) {
        throw failureFor(error);
      }
      const { input_tokens: inputTokens, output_tokens: outputTokens } =
        message.usage;
      if (
        !Number.isSafeInteger(inputTokens) ||
        inputTokens < 0 ||
        !Number.isSafeInteger(outputTokens) ||
        outputTokens < 0
      )
        throw new AIProviderFailure("invalid_provider_response", "uncertain");
      return {
        // Thinking blocks are ignored; only the written answer is used.
        text: message.content
          .flatMap((block) => (block.type === "text" ? [block.text] : []))
          .join("\n"),
        inputTokens,
        outputTokens,
        stopReason: message.stop_reason ?? "unknown",
        model: message.model,
      };
    },
  };
}

let override: AIProvider | null = null;

/** Unit tests use a scripted provider so nothing reaches the network. */
export function setAIProviderForTests(provider: AIProvider | null) {
  override = provider;
}

export function getAIProvider(): AIProvider {
  return override ?? anthropicProvider();
}
