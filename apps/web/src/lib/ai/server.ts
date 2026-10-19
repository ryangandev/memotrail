import "server-only";
import { aiFeatureAvailable, AI_PAUSED_MESSAGE } from "./availability";
import { createClient as supabaseClient } from "@supabase/supabase-js";
import { authenticateAPI, APIError } from "@/lib/auth/api";
import { requireSupabasePublicConfig } from "@/lib/supabase/config";
import {
  AI_MODEL,
  aiModelPricing,
  REVIEW_MODEL,
  type AIRequestFeature,
} from "./contracts";
import { imageContent, AI_PHOTO_RESERVE, type AIImage } from "./image-input";
import { AIProviderFailure, getAIProvider, readAIBaseURL } from "./provider";

export class AIError extends APIError {}

type Gated = AIRequestFeature | "connection";

/** The paused features can be given a feature to authenticate for; unnamed callers stay paused. */
export async function authenticateAI(
  request: Request,
  feature: Gated = "connection",
) {
  assertAIAvailable(feature);
  try {
    return await authenticateAPI(request);
  } catch (error) {
    if (error instanceof APIError)
      throw new AIError(error.code, error.status, error.message);
    throw error;
  }
}

export function aiProviderConfigured() {
  return (
    process.env.AI_PROVIDER === "anthropic" &&
    Boolean(process.env.AI_API_KEY?.trim()) &&
    Boolean(process.env.SUPABASE_SECRET_KEY?.trim()) &&
    (!process.env.AI_CHAT_MODEL || process.env.AI_CHAT_MODEL === AI_MODEL) &&
    (!process.env.AI_REVIEW_MODEL ||
      process.env.AI_REVIEW_MODEL === REVIEW_MODEL) &&
    readAIBaseURL().ok
  );
}

export function assertAIAvailable(feature: Gated) {
  if (!aiFeatureAvailable(feature))
    throw new AIError("ai_paused", 503, AI_PAUSED_MESSAGE);
}

/** Per request: the largest prompt, answer, and wait each feature may use. */
const featureLimits: Record<
  Gated,
  { promptBytes: number; maxTokens: number; timeoutMs: number }
> = {
  connection: { promptBytes: 64_000, maxTokens: 2048, timeoutMs: 25_000 },
  classification: { promptBytes: 64_000, maxTokens: 2048, timeoutMs: 25_000 },
  tagging: { promptBytes: 64_000, maxTokens: 2048, timeoutMs: 25_000 },
  search: { promptBytes: 64_000, maxTokens: 2048, timeoutMs: 25_000 },
  explore: { promptBytes: 64_000, maxTokens: 2048, timeoutMs: 25_000 },
  resurfacing: { promptBytes: 64_000, maxTokens: 2048, timeoutMs: 25_000 },
  photo_analysis: { promptBytes: 64_000, maxTokens: 2048, timeoutMs: 25_000 },
  review: { promptBytes: 800_000, maxTokens: 16_000, timeoutMs: 240_000 },
  chapter_suggestion: {
    promptBytes: 160_000,
    maxTokens: 6_000,
    timeoutMs: 120_000,
  },
};
/** A single reservation never exceeds two dollars, the same bound the database enforces. */
const MAX_RESERVATION_MICROS = 2_000_000;

export type AIRequestOptions = {
  ownerID: string;
  feature: Gated;
  system: string;
  input: string;
  maxTokens?: number;
  schema?: Record<string, unknown>;
  images?: AIImage[];
  /** Defaults to the review model for reviews and suggestions, otherwise the paused features' model. */
  model?: string;
  effort?: "low" | "medium" | "high";
  timeoutMs?: number;
};

function monthlyBudgetMicros(
  name: string,
  fallback: string,
  ceiling: number,
): number | null {
  const raw = process.env[name]?.trim() || fallback;
  const dollars = Number(raw);
  if (!Number.isFinite(dollars) || dollars <= 0 || dollars > ceiling)
    return null;
  return Math.floor(dollars * 1_000_000);
}

/** The server-wide and per-person monthly budgets, in micro-dollars, or null when misconfigured. */
export function aiMonthlyBudgets() {
  const server = monthlyBudgetMicros("AI_MONTHLY_BUDGET_USD", "25", 1000);
  const user = monthlyBudgetMicros("AI_USER_MONTHLY_BUDGET_USD", "3", 100);
  return server && user ? { server, user } : null;
}

export function aiAdminClient() {
  return supabaseClient(
    requireSupabasePublicConfig().url,
    process.env.SUPABASE_SECRET_KEY!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
}

const providerMessages: Record<string, [number, string]> = {
  provider_authentication: [
    502,
    "The AI provider could not complete this request. Check AI settings before retrying.",
  ],
  provider_error: [
    502,
    "The AI provider could not complete this request. Check AI settings before retrying.",
  ],
  provider_interrupted: [
    502,
    "The AI request was interrupted. Its budget reservation is retained because provider billing is uncertain.",
  ],
  provider_unavailable: [
    503,
    "AI is not configured on this server. Manual features still work.",
  ],
  invalid_provider_response: [
    502,
    "The provider returned an incomplete usage record.",
  ],
};

export async function requestAI(options: AIRequestOptions) {
  const { ownerID, feature, system, input } = options;
  assertAIAvailable(feature);
  if (!aiProviderConfigured())
    throw new AIError(
      "provider_unavailable",
      503,
      "AI is not configured on this server. Manual features still work.",
    );
  const limits = featureLimits[feature];
  const maxTokens = options.maxTokens ?? 1024;
  const model =
    options.model ??
    (feature === "review" || feature === "chapter_suggestion"
      ? REVIEW_MODEL
      : AI_MODEL);
  const price = aiModelPricing[model];
  const images = options.images ?? [];
  // A UTF-8 byte bound conservatively exceeds text token counts, including Unicode.
  const promptBytes = Buffer.byteLength(
    system + input + (options.schema ? JSON.stringify(options.schema) : ""),
    "utf8",
  );
  const reserve = price
    ? promptBytes * price.inputMicros +
      maxTokens * price.outputMicros +
      4096 * price.inputMicros +
      images.length * AI_PHOTO_RESERVE * price.inputMicros
    : Infinity;
  if (
    !price ||
    promptBytes > limits.promptBytes ||
    !Number.isInteger(maxTokens) ||
    maxTokens < 1 ||
    maxTokens > limits.maxTokens ||
    reserve > MAX_RESERVATION_MICROS
  )
    throw new AIError(
      "request_too_large",
      413,
      "Use a shorter passage for AI.",
    );
  let imageBlocks: ReturnType<typeof imageContent>;
  try {
    if (images.length && feature !== "photo_analysis") throw Error();
    imageBlocks = imageContent(images);
  } catch {
    throw new AIError(
      "invalid_images",
      400,
      "Photo input is invalid. Nothing was sent.",
    );
  }
  const budgets = aiMonthlyBudgets();
  if (!budgets)
    throw new AIError(
      "invalid_budget",
      503,
      "The server AI budget needs configuration.",
    );
  const admin = aiAdminClient();
  const { data: usageID, error } = await admin.rpc("reserve_ai_usage", {
    p_owner_id: ownerID,
    p_feature: feature,
    p_model: model,
    p_reserved_micros: reserve,
    p_global_budget_micros: budgets.server,
    p_user_budget_micros: budgets.user,
  });
  if (error || !usageID) {
    if (error?.message === "ai_disabled")
      throw new AIError(
        "ai_disabled",
        403,
        "Enable this AI feature in Settings first.",
      );
    if (error?.message === "ai_budget_exceeded")
      throw new AIError(
        "budget_exceeded",
        429,
        "The monthly or server AI budget is reached. Manual features still work.",
      );
    if (error?.message === "ai_rate_limit")
      throw new AIError(
        "rate_limit",
        429,
        "Too many AI requests. Try again later.",
      );
    throw new AIError(
      "usage_unavailable",
      503,
      "Could not reserve the AI budget. Nothing was sent to the provider.",
    );
  }
  let status = "uncertain";
  let inputTokens: number | null = null,
    outputTokens: number | null = null;
  let code: string | null = "provider_interrupted";
  try {
    const result = await getAIProvider().generate({
      model,
      system,
      input,
      images: imageBlocks,
      maxTokens,
      schema: options.schema,
      effort: options.effort,
      timeoutMs: options.timeoutMs ?? limits.timeoutMs,
    });
    inputTokens = result.inputTokens;
    outputTokens = result.outputTokens;
    // The provider billed this request even when its answer cannot be used.
    status = "completed";
    code = null;
    if (result.stopReason === "refusal") {
      code = "review_declined";
      throw new AIError(
        "review_declined",
        502,
        "The AI model declined this request. Your Entries are unchanged.",
      );
    }
    if (
      !result.text ||
      result.stopReason !== "end_turn"
    ) {
      code = "incomplete_generation";
      throw new AIError(
        "incomplete_generation",
        502,
        "AI could not finish its response. Your Entry has not changed.",
      );
    }
    return {
      text: result.text,
      usageID: usageID as string,
      model,
      inputTokens: result.inputTokens,
      outputTokens: result.outputTokens,
    };
  } catch (error) {
    if (error instanceof AIError) throw error;
    const failure =
      error instanceof AIProviderFailure
        ? error
        : new AIProviderFailure("provider_interrupted", "uncertain");
    status = failure.outcome;
    code = failure.code;
    const [httpStatus, message] =
      providerMessages[failure.code] ?? providerMessages.provider_interrupted;
    throw new AIError(failure.code, httpStatus, message);
  } finally {
    // On a database/network failure the original reservation remains charged, never free retry credit.
    await admin
      .rpc("finish_ai_usage", {
        p_id: usageID,
        p_status: status,
        p_input_tokens: inputTokens,
        p_output_tokens: outputTokens,
        p_error_code: code,
      })
      .then(
        () => undefined,
        () => undefined,
      );
  }
}

/** The original positional form, kept for the paused features' callers. */
export async function generateAI(
  ownerID: string,
  feature: Gated,
  system: string,
  prompt: string,
  maxTokens = 1024,
  outputSchema?: Record<string, unknown>,
  images: AIImage[] = [],
) {
  const { text, usageID, model } = await requestAI({
    ownerID,
    feature,
    system,
    input: prompt,
    maxTokens,
    schema: outputSchema,
    images,
  });
  return { text, usageID, model };
}

export function aiErrorResponse(error: unknown) {
  const safe =
    error instanceof AIError
      ? error
      : new AIError(
          "unavailable",
          503,
          "AI is temporarily unavailable. Your records are unchanged.",
        );
  return Response.json(
    { error: safe.message, code: safe.code },
    { status: safe.status, headers: { "Cache-Control": "no-store" } },
  );
}
