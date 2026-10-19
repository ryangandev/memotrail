import "server-only";
import { after } from "next/server";
import { chunkEntryText } from "./chunking";
import {
  embedDocuments,
  semanticSearchConfigured,
  type DocumentEmbeddingResult,
} from "./embedding-client";
import { SEMANTIC_MODEL, formatDocumentForModel } from "./semantic-config";

/** The part of the signed-in Supabase client that indexing needs. */
export type SearchIndexClient = {
  rpc: (
    fn: string,
    args?: Record<string, unknown>,
  ) => PromiseLike<{ data: unknown; error: { message?: string } | null }>;
};

export type DrainResult = {
  indexed: number;
  /** Entries that changed while being embedded and wait for the next drain. */
  stale: number;
  /** Entries the service refused, now backing off. */
  rejected: number;
  stoppedBecause: "budget" | "busy" | "error" | "idle" | "unavailable";
};

type Job = {
  body: string;
  entryId: string;
  sourceHash: string;
  title: string | null;
};

const CLAIM_BATCH = 4;
const DEFAULT_BUDGET_MS = 90_000;
const activeOwners = new Set<string>();

/**
 * Indexes the signed-in user's stale Entries until none are left or the budget is
 * spent. Postgres decides what is stale; this only claims, embeds, and stores, so it
 * needs no service-role key. An unavailable service stops the drain without counting a
 * failure, so an outage never burns an Entry's attempts.
 */
export async function drainSearchIndex(
  client: SearchIndexClient,
  ownerId: string,
  options: {
    budgetMs?: number;
    embed?: (texts: readonly string[]) => Promise<DocumentEmbeddingResult>;
    now?: () => number;
  } = {},
): Promise<DrainResult> {
  const result: DrainResult = {
    indexed: 0,
    rejected: 0,
    stale: 0,
    stoppedBecause: "idle",
  };
  // One drain per owner per instance; `skip locked` covers other instances.
  if (activeOwners.has(ownerId)) return { ...result, stoppedBecause: "busy" };
  activeOwners.add(ownerId);

  const embed = options.embed ?? embedDocuments;
  const now = options.now ?? Date.now;
  const deadline = now() + (options.budgetMs ?? DEFAULT_BUDGET_MS);

  try {
    for (;;) {
      if (now() >= deadline) return { ...result, stoppedBecause: "budget" };

      const claimed = await client.rpc("claim_entry_search_index_jobs", {
        p_limit: CLAIM_BATCH,
        p_model: SEMANTIC_MODEL,
      });
      const jobs = claimed.error ? null : parseJobs(claimed.data);
      if (!jobs) return { ...result, stoppedBecause: "error" };
      if (jobs.length === 0) return { ...result, stoppedBecause: "idle" };

      for (const job of jobs) {
        if (now() >= deadline) return { ...result, stoppedBecause: "budget" };
        const outcome = await indexJob(client, job, embed);
        if (outcome === "unavailable") {
          return { ...result, stoppedBecause: "unavailable" };
        }
        if (outcome === "error") return { ...result, stoppedBecause: "error" };
        result[outcome] += 1;
      }
    }
  } finally {
    activeOwners.delete(ownerId);
  }
}

async function indexJob(
  client: SearchIndexClient,
  job: Job,
  embed: (texts: readonly string[]) => Promise<DocumentEmbeddingResult>,
): Promise<"error" | "indexed" | "rejected" | "stale" | "unavailable"> {
  const chunks = chunkEntryText({ body: job.body, title: job.title });
  const embedded = chunks.length
    ? await embed(
        chunks.map((chunk) => formatDocumentForModel(job.title, chunk.text)),
      )
    : ({ status: "ok", vectors: [] } as const);

  if (embedded.status === "unavailable") return "unavailable";
  if (embedded.status === "rejected") {
    const failed = await client.rpc("fail_entry_search_index_job", {
      p_entry_id: job.entryId,
      p_error: failureCode(embedded.reason),
      p_source_hash: job.sourceHash,
    });
    return failed.error ? "error" : "rejected";
  }
  if (embedded.vectors.length !== chunks.length) return "error";

  const stored = await client.rpc("store_entry_search_chunks", {
    p_chunks: chunks.map((chunk, position) => ({
      embedding: embedded.vectors[position].map(
        (component) => Math.round(component * 1e6) / 1e6,
      ),
      end: chunk.end,
      index: chunk.index,
      start: chunk.start,
    })),
    p_entry_id: job.entryId,
    p_model: SEMANTIC_MODEL,
    p_source_hash: job.sourceHash,
  });
  if (stored.error) return "error";
  // False means the Entry changed or was removed meanwhile; it stays due.
  return stored.data === true ? "indexed" : "stale";
}

function failureCode(reason: string) {
  return /^[a-z_]{1,64}$/.test(reason) ? reason : "input_rejected";
}

function parseJobs(value: unknown): Job[] | null {
  if (!Array.isArray(value)) return null;
  const jobs: Job[] = [];
  for (const row of value) {
    if (typeof row !== "object" || row === null) return null;
    const { body, entry_id, source_hash, title } = row as Record<
      string,
      unknown
    >;
    if (
      typeof body !== "string" ||
      typeof entry_id !== "string" ||
      typeof source_hash !== "string" ||
      (title !== null && typeof title !== "string")
    ) {
      return null;
    }
    jobs.push({
      body,
      entryId: entry_id,
      sourceHash: source_hash,
      title: title as string | null,
    });
  }
  return jobs;
}

/**
 * Drains after the response, so saving or searching never waits for the model. A no-op
 * without an embedding service, which keeps local development and Preview untouched.
 */
export function scheduleSearchIndexDrain(
  client: SearchIndexClient,
  ownerId: string,
) {
  if (!semanticSearchConfigured()) return;
  after(async () => {
    await drainSearchIndex(client, ownerId).catch(() => undefined);
  });
}
