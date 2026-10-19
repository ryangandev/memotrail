import "server-only";
import { embedQuery, semanticSearchConfigured } from "./embedding-client";
import {
  scheduleSearchIndexDrain,
  type SearchIndexClient,
} from "./search-index";
import {
  MERGED_SEARCH_AVAILABLE,
  QUERY_TIMEOUT_MS,
  SEMANTIC_MIN_SIMILARITY,
  SEMANTIC_MODEL,
  queryUsesMeaning,
} from "./semantic-config";
import {
  KEYWORD_ONLY_STATUS,
  type SemanticSearchStatus,
} from "./semantic-state";

/** The extra `search_wiki_items` arguments of the merged search (migration 0023). */
export type SemanticSearchArguments = {
  p_embedding_model: string;
  p_query_embedding: number[];
  p_semantic_min_similarity: number;
};

export type PreparedSemanticSearch = {
  /** Null sends exactly today's keyword-only call. */
  arguments: SemanticSearchArguments | null;
  status: SemanticSearchStatus;
};

/**
 * Decides, before one search, whether to ask the embedding service about the query.
 * Any doubt - no service, no migration, a Settings opt-out, an outage - resolves to
 * keyword-only search, and a pending backlog schedules an indexing drain.
 */
export async function prepareSemanticSearch(
  client: SearchIndexClient,
  ownerId: string,
  query: string,
  mode: keyof typeof QUERY_TIMEOUT_MS,
): Promise<PreparedSemanticSearch> {
  const keywordOnly = { arguments: null, status: KEYWORD_ONLY_STATUS };
  if (!semanticSearchConfigured()) return keywordOnly;

  const indexStatus = await client.rpc("search_index_status", {
    p_model: SEMANTIC_MODEL,
  });
  const row = indexStatus.error ? null : statusRow(indexStatus.data);
  // Without the index functions the database predates this feature.
  if (!row) return keywordOnly;

  if (!row.enabled) {
    return { arguments: null, status: { pendingCount: 0, state: "off" } };
  }
  if (row.pending > 0) scheduleSearchIndexDrain(client, ownerId);
  if (!MERGED_SEARCH_AVAILABLE) return keywordOnly;

  const pendingCount = row.pending;
  if (!queryUsesMeaning(query)) {
    return { arguments: null, status: { pendingCount, state: "on" } };
  }

  const embedded = await embedQuery(query, {
    timeoutMs: QUERY_TIMEOUT_MS[mode],
  });
  if (embedded.status !== "ok") {
    return { arguments: null, status: { pendingCount, state: "unavailable" } };
  }
  return {
    arguments: {
      p_embedding_model: SEMANTIC_MODEL,
      p_query_embedding: embedded.vector,
      p_semantic_min_similarity: SEMANTIC_MIN_SIMILARITY,
    },
    status: { pendingCount, state: "on" },
  };
}

function statusRow(
  value: unknown,
): { enabled: boolean; pending: number } | null {
  const row = Array.isArray(value) ? value[0] : null;
  if (typeof row !== "object" || row === null) return null;
  const { enabled, pending } = row as Record<string, unknown>;
  return typeof enabled === "boolean" &&
    typeof pending === "number" &&
    Number.isSafeInteger(pending) &&
    pending >= 0
    ? { enabled, pending }
    : null;
}
