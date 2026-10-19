import "server-only";
import { createHash } from "node:crypto";
import {
  DOCUMENT_BATCH_SIZE,
  DOCUMENT_TIMEOUT_MS,
  SEMANTIC_DIMENSIONS,
  SEMANTIC_MODEL,
  formatQueryForModel,
} from "./semantic-config";

/**
 * The only place that talks to MemoTrail's own embedding service (Text Embeddings
 * Inference behind an OpenAI-compatible route). It never logs query or Entry text,
 * only short reason codes.
 */
export type EmbeddingFailureReason =
  | "bad_response"
  | "model_mismatch"
  | "not_configured"
  | "timeout"
  | "unavailable";

export type QueryEmbeddingResult =
  | { status: "ok"; vector: number[] }
  | { reason: EmbeddingFailureReason; status: "unavailable" };

export type DocumentEmbeddingResult =
  | { status: "ok"; vectors: number[][] }
  /** The service refused this text; retrying the same text will not help. */
  | { reason: string; status: "rejected" }
  | { reason: EmbeddingFailureReason; status: "unavailable" };

type ServiceConfig = { apiKey: string; baseUrl: string };

const BREAKER_MS = 30_000;
const CACHE_LIMIT = 256;
const CACHE_TTL_MS = 10 * 60_000;

let breakerUntil = 0;
const queryCache = new Map<string, { expires: number; vector: number[] }>();

/** The service is configured with a real address and key, over HTTPS or loopback. */
export function readServiceConfig(
  env: Record<string, string | undefined> = process.env,
): ServiceConfig | null {
  const rawUrl = env.SEMANTIC_SEARCH_URL?.trim();
  const apiKey = env.SEMANTIC_SEARCH_API_KEY?.trim();
  if (!rawUrl || !apiKey) return null;

  try {
    const url = new URL(rawUrl);
    const loopback = ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname);
    if (url.protocol !== "https:" && !(url.protocol === "http:" && loopback)) {
      return null;
    }
    return { apiKey, baseUrl: url.origin + url.pathname.replace(/\/+$/, "") };
  } catch {
    return null;
  }
}

export function semanticSearchConfigured() {
  return readServiceConfig() !== null;
}

export function resetEmbeddingClientState() {
  breakerUntil = 0;
  queryCache.clear();
}

export async function embedQuery(
  query: string,
  options: { timeoutMs: number },
): Promise<QueryEmbeddingResult> {
  const config = readServiceConfig();
  if (!config) return { reason: "not_configured", status: "unavailable" };
  if (Date.now() < breakerUntil) {
    return { reason: "unavailable", status: "unavailable" };
  }

  const key = createHash("sha256")
    .update(`${SEMANTIC_MODEL}\n${query}`)
    .digest("hex");
  const cached = queryCache.get(key);
  if (cached && cached.expires > Date.now()) {
    // Refresh recency so a repeated query stays near the end of the map.
    queryCache.delete(key);
    queryCache.set(key, cached);
    return { status: "ok", vector: cached.vector };
  }

  const result = await requestEmbeddings(config, [formatQueryForModel(query)], {
    timeoutMs: options.timeoutMs,
  });
  if (result.status !== "ok") {
    return result.status === "rejected"
      ? { reason: "bad_response", status: "unavailable" }
      : result;
  }

  const vector = result.vectors[0];
  queryCache.set(key, { expires: Date.now() + CACHE_TTL_MS, vector });
  while (queryCache.size > CACHE_LIMIT) {
    const oldest = queryCache.keys().next().value;
    if (oldest === undefined) break;
    queryCache.delete(oldest);
  }
  return { status: "ok", vector };
}

export async function embedDocuments(
  texts: readonly string[],
): Promise<DocumentEmbeddingResult> {
  const config = readServiceConfig();
  if (!config) return { reason: "not_configured", status: "unavailable" };
  if (Date.now() < breakerUntil) {
    return { reason: "unavailable", status: "unavailable" };
  }

  const vectors: number[][] = [];
  for (let from = 0; from < texts.length; from += DOCUMENT_BATCH_SIZE) {
    const result = await requestEmbeddings(
      config,
      texts.slice(from, from + DOCUMENT_BATCH_SIZE),
      { timeoutMs: DOCUMENT_TIMEOUT_MS },
    );
    if (result.status !== "ok") return result;
    vectors.push(...result.vectors);
  }
  return { status: "ok", vectors };
}

type RawResult =
  | { status: "ok"; vectors: number[][] }
  | { reason: string; status: "rejected" }
  | { reason: EmbeddingFailureReason; status: "unavailable" };

async function requestEmbeddings(
  config: ServiceConfig,
  input: readonly string[],
  options: { timeoutMs: number },
): Promise<RawResult> {
  let response: Response;
  try {
    response = await fetch(`${config.baseUrl}/v1/embeddings`, {
      body: JSON.stringify({ input, model: SEMANTIC_MODEL }),
      cache: "no-store",
      headers: {
        Authorization: `Bearer ${config.apiKey}`,
        "Content-Type": "application/json",
      },
      method: "POST",
      signal: AbortSignal.timeout(options.timeoutMs),
    });
  } catch (error) {
    const timedOut =
      error instanceof Error &&
      (error.name === "TimeoutError" || error.name === "AbortError");
    return outage(timedOut ? "timeout" : "unavailable");
  }

  if (response.status === 413 || response.status === 422) {
    return { reason: "input_rejected", status: "rejected" };
  }
  // 401, 403, 429, and 5xx all mean the service cannot answer right now.
  if (!response.ok) return outage("unavailable");

  let payload: unknown;
  try {
    payload = await response.json();
  } catch {
    return outage("bad_response");
  }

  const parsed = parseEmbeddingsPayload(payload, input.length);
  if (parsed === "model_mismatch") return outage("model_mismatch");
  if (!parsed) return outage("bad_response");
  return { status: "ok", vectors: parsed };
}

/** An outage opens the breaker so typing does not pay the timeout on every key. */
function outage(reason: EmbeddingFailureReason): RawResult {
  breakerUntil = Date.now() + BREAKER_MS;
  console.warn(`[semantic-search] ${reason}`);
  return { reason, status: "unavailable" };
}

function parseEmbeddingsPayload(
  payload: unknown,
  expected: number,
): number[][] | "model_mismatch" | null {
  if (typeof payload !== "object" || payload === null) return null;
  const { data, model } = payload as { data?: unknown; model?: unknown };
  // A service that names its model must name ours; vectors from another model are useless.
  if (typeof model === "string" && model !== SEMANTIC_MODEL) {
    return "model_mismatch";
  }
  if (!Array.isArray(data) || data.length !== expected) return null;

  const ordered: (number[] | undefined)[] = new Array(expected);
  for (const item of data) {
    if (typeof item !== "object" || item === null) return null;
    const { embedding, index } = item as {
      embedding?: unknown;
      index?: unknown;
    };
    if (
      !Number.isInteger(index) ||
      (index as number) < 0 ||
      (index as number) >= expected ||
      ordered[index as number] !== undefined
    ) {
      return null;
    }
    const vector = normalized(embedding);
    if (!vector) return null;
    ordered[index as number] = vector;
  }
  return ordered.every((vector) => vector !== undefined)
    ? (ordered as number[][])
    : null;
}

/** L2-normalized, or null for a wrong size, a non-number, or a zero vector. */
function normalized(value: unknown): number[] | null {
  if (!Array.isArray(value) || value.length !== SEMANTIC_DIMENSIONS)
    return null;
  let energy = 0;
  for (const component of value) {
    if (typeof component !== "number" || !Number.isFinite(component)) {
      return null;
    }
    energy += component * component;
  }
  if (!(energy > 0) || !Number.isFinite(energy)) return null;
  const norm = Math.sqrt(energy);
  return (value as number[]).map((component) => component / norm);
}
