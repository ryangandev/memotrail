import model from "./semantic-model.json";

/**
 * The one place that names the embedding model. Switching models means editing
 * `semantic-model.json` (and, for a different vector size, the `halfvec(...)` size in
 * the semantic search migration); the eval script, the embedding service image, and the
 * consistency test all read the same file.
 */
export const SEMANTIC_DIMENSIONS: number = model.dimensions;

/** Stored with every vector, so vectors from another model never match a query. */
export const SEMANTIC_MODEL = `${model.huggingFaceId}@${model.revision.slice(0, 12)}`;

/** The similarity floor below which a chunk is not a meaning match. */
export const SEMANTIC_MIN_SIMILARITY: number = model.minSimilarity;

export const QUERY_TIMEOUT_MS = { library: 1200, quick: 600 } as const;

/** Documents are embedded in batches no larger than this. */
export const DOCUMENT_BATCH_SIZE = 8;
export const DOCUMENT_TIMEOUT_MS = 30_000;

/**
 * Whether the deployed database has the merged keyword-and-meaning
 * `search_wiki_items` (migration 202610190023). Set it to false to send no query vector,
 * which keeps results keyword-only against a database that predates that migration.
 * Indexing runs either way once the embedding service is configured.
 */
export const MERGED_SEARCH_AVAILABLE = true;

export function formatQueryForModel(query: string) {
  return model.queryTemplate
    .replace("{instruction}", () => model.queryInstruction)
    .replace("{query}", () => query);
}

/** The text embedded for one chunk: the title gives each chunk its context. */
export function formatDocumentForModel(
  title: string | null,
  chunkText: string,
) {
  const heading = title?.trim();
  return heading ? `${heading}\n\n${chunkText}` : chunkText;
}

/** Queries that cannot gain from meaning: a single character or an exact phrase. */
export function queryUsesMeaning(query: string) {
  const trimmed = query.trim();
  if (Array.from(trimmed).length < 2) return false;
  return !(trimmed.startsWith('"') && trimmed.endsWith('"'));
}
