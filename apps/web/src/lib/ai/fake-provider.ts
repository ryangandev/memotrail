import {
  AIProviderFailure,
  type AIProvider,
  type AIProviderRequest,
  type AIProviderResult,
} from "./provider";

/**
 * A scripted provider for unit tests. It records every request and answers from a queue,
 * so a test can assert exactly what was sent and that nothing else was. Test-only.
 */
export type FakeStep =
  | AIProviderResult
  | AIProviderFailure
  | ((
      request: AIProviderRequest,
    ) => AIProviderResult | AIProviderFailure | Promise<AIProviderResult | AIProviderFailure>);

export function fakeProvider(...steps: FakeStep[]) {
  const requests: AIProviderRequest[] = [];
  const queue = [...steps];
  const provider: AIProvider = {
    async generate(request) {
      requests.push(request);
      const step = queue.shift();
      if (!step) throw new Error("The fake provider ran out of scripted answers");
      const outcome = typeof step === "function" ? await step(request) : step;
      if (outcome instanceof AIProviderFailure) throw outcome;
      return outcome;
    },
  };
  return { provider, requests, remaining: () => queue.length };
}

export function completed(
  value: unknown,
  usage: { inputTokens?: number; outputTokens?: number } = {},
): AIProviderResult {
  return {
    text: typeof value === "string" ? value : JSON.stringify(value),
    inputTokens: usage.inputTokens ?? 1000,
    outputTokens: usage.outputTokens ?? 200,
    stopReason: "end_turn",
    model: "claude-sonnet-5-5",
  };
}

/** The model declined; the provider still billed the request. */
export function refusal(): AIProviderResult {
  return { ...completed(""), stopReason: "refusal" };
}

/** The answer was cut off at the token limit. */
export function cutOff(): AIProviderResult {
  return { ...completed('{"summary":"A'), stopReason: "max_tokens" };
}

/** The connection dropped or timed out: the outcome, and the bill, are unknown. */
export function interrupted() {
  return new AIProviderFailure("provider_interrupted", "uncertain");
}

/** The provider was overloaded. */
export function outage() {
  return new AIProviderFailure("provider_error", "uncertain");
}

/** The provider rejected the request outright. */
export function rejected() {
  return new AIProviderFailure("provider_error", "failed");
}
