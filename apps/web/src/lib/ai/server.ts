import "server-only";
import { AI_CAPABILITIES_AVAILABLE, AI_PAUSED_MESSAGE } from "./availability";
import { createClient as supabaseClient } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/server";
import { requireSupabasePublicConfig } from "@/lib/supabase/config";
import { AI_MODEL, aiOriginAllowed, type AIFeature } from "./contracts";
import { imageContent, AI_PHOTO_RESERVE, type AIImage } from "./image-input";

export class AIError extends Error {
  constructor(
    public code: string,
    public status: number,
    message: string,
  ) {
    super(message);
  }
}

export async function authenticateAI(request: Request) {
  assertAIAvailable();
  const authorization = request.headers.get("authorization");
  const bearer = authorization?.startsWith("Bearer ") === true;
  if (!aiOriginAllowed(request, bearer, process.env.NEXT_PUBLIC_APP_URL))
    throw new AIError(
      "invalid_origin",
      403,
      "This request must come from MemoTrail.",
    );
  const { url, publishableKey } = requireSupabasePublicConfig();
  const client = bearer
    ? supabaseClient(url, publishableKey, {
        auth: { persistSession: false, autoRefreshToken: false },
        global: { headers: { Authorization: authorization! } },
      })
    : await createClient();
  const { data, error } = await client.auth.getUser(
    bearer ? authorization!.slice(7) : undefined,
  );
  if (error || !data.user)
    throw new AIError(
      "authentication_required",
      401,
      "Sign in again to use AI.",
    );
  return { client, ownerID: data.user.id };
}

export function aiProviderConfigured() {
  return (
    process.env.AI_PROVIDER === "anthropic" &&
    Boolean(process.env.AI_API_KEY?.trim()) &&
    Boolean(process.env.SUPABASE_SECRET_KEY?.trim()) &&
    (!process.env.AI_CHAT_MODEL || process.env.AI_CHAT_MODEL === AI_MODEL)
  );
}

export function assertAIAvailable() {
  if (!AI_CAPABILITIES_AVAILABLE)
    throw new AIError("ai_paused", 503, AI_PAUSED_MESSAGE);
}

export async function generateAI(
  ownerID: string,
  feature: AIFeature | "connection",
  system: string,
  prompt: string,
  maxTokens = 1024,
  outputSchema?: Record<string, unknown>,
  images: AIImage[] = [],
) {
  assertAIAvailable();
  if (!aiProviderConfigured())
    throw new AIError(
      "provider_unavailable",
      503,
      "AI is not configured on this server. Manual features still work.",
    );
  // A UTF-8 byte bound conservatively exceeds text token counts, including Unicode.
  const promptBytes = Buffer.byteLength(
    system + prompt + (outputSchema ? JSON.stringify(outputSchema) : ""),
    "utf8",
  );
  if (
    promptBytes > 64_000 ||
    !Number.isInteger(maxTokens) ||
    maxTokens < 1 ||
    maxTokens > 2048
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
  const reserve =
    promptBytes + 4096 + maxTokens * 5 + images.length * AI_PHOTO_RESERVE;
  const budget = Number(process.env.AI_TOTAL_BUDGET_USD ?? "3");
  if (!Number.isFinite(budget) || budget <= 0 || budget > 100)
    throw new AIError(
      "invalid_budget",
      503,
      "The server AI budget needs configuration.",
    );
  const admin = supabaseClient(
    requireSupabasePublicConfig().url,
    process.env.SUPABASE_SECRET_KEY!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
  const { data: usageID, error } = await admin.rpc("reserve_ai_usage", {
    p_owner_id: ownerID,
    p_feature: feature,
    p_model: AI_MODEL,
    p_reserved_micros: reserve,
    p_global_budget_micros: Math.floor(budget * 1_000_000),
  });
  if (error || !usageID) {
    if (error?.message === "ai_disabled")
      throw new AIError(
        "ai_disabled",
        403,
        "Enable this AI feature in AI settings first.",
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
    const response = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": process.env.AI_API_KEY!.trim(),
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: AI_MODEL,
        max_tokens: maxTokens,
        system,
        messages: [
          {
            role: "user",
            content: imageBlocks.length
              ? [...imageBlocks, { type: "text", text: prompt }]
              : prompt,
          },
        ],
        ...(outputSchema
          ? {
              output_config: {
                format: { type: "json_schema", schema: outputSchema },
              },
            }
          : {}),
      }),
      signal: AbortSignal.timeout(25_000),
      cache: "no-store",
    });
    if (!response.ok) {
      status =
        response.status >= 400 && response.status < 500
          ? "failed"
          : "uncertain";
      code =
        response.status === 401 ? "provider_authentication" : "provider_error";
      throw new AIError(
        code,
        502,
        "The AI provider could not complete this request. Check AI settings before retrying.",
      );
    }
    const data = await response.json();
    if (
      !Number.isSafeInteger(data.usage?.input_tokens) ||
      data.usage.input_tokens < 0 ||
      !Number.isSafeInteger(data.usage?.output_tokens) ||
      data.usage.output_tokens < 0
    )
      throw new AIError(
        "invalid_provider_response",
        502,
        "The provider returned an incomplete usage record.",
      );
    inputTokens = data.usage.input_tokens;
    outputTokens = data.usage.output_tokens;
    status = "completed";
    code = null;
    const text = Array.isArray(data.content)
      ? data.content
          .filter(
            (b: { type?: string; text?: unknown }) =>
              b.type === "text" && typeof b.text === "string",
          )
          .map((b: { text: string }) => b.text)
          .join("\n")
      : "";
    if (!text || data.stop_reason !== "end_turn")
      throw new AIError(
        "incomplete_generation",
        502,
        "AI could not finish its response. Your Entry has not changed.",
      );
    return { text, usageID, model: AI_MODEL };
  } catch (error) {
    if (error instanceof AIError) throw error;
    throw new AIError(
      "provider_interrupted",
      502,
      "The AI request was interrupted. Its budget reservation is retained because provider billing is uncertain.",
    );
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
