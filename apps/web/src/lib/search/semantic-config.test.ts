import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import model from "./semantic-model.json";
import {
  MERGED_SEARCH_AVAILABLE,
  SEMANTIC_DIMENSIONS,
  SEMANTIC_MIN_SIMILARITY,
  SEMANTIC_MODEL,
  formatDocumentForModel,
  formatQueryForModel,
  queryUsesMeaning,
} from "./semantic-config";

const read = (path: string) =>
  readFileSync(new URL(path, import.meta.url), "utf8");

describe("the model configuration", () => {
  it("labels vectors with the model and a twelve-character revision", () => {
    expect(SEMANTIC_MODEL).toBe(
      `Qwen/Qwen3-Embedding-0.6B@${model.revision.slice(0, 12)}`,
    );
    expect(model.revision).toMatch(/^[0-9a-f]{40}$/);
    // The label must pass the database's check on model names.
    expect(SEMANTIC_MODEL).toMatch(/^[A-Za-z0-9._/@:-]{1,120}$/);
  });

  it("keeps the similarity floor a sensible cosine value", () => {
    expect(SEMANTIC_MIN_SIMILARITY).toBeGreaterThan(0);
    expect(SEMANTIC_MIN_SIMILARITY).toBeLessThan(1);
  });

  it("matches the vector size the migration stores", () => {
    const migration = read(
      "../../../../../supabase/migrations/202610190020_semantic_search_index.sql",
    );
    expect(migration).toContain(`extensions.halfvec(${SEMANTIC_DIMENSIONS})`);
  });

  it("matches the model the embedding service image bakes in", () => {
    const dockerfile = read("../../../../../services/embeddings/Dockerfile");
    expect(dockerfile).toContain(`ARG MODEL_ID=${model.huggingFaceId}`);
    expect(dockerfile).toContain(`ARG MODEL_REVISION=${model.revision}`);
    expect(dockerfile).toContain(`"--served-model-name", "${SEMANTIC_MODEL}"`);
  });

  it("sends query vectors now that the merged search migration exists", () => {
    const migration = read(
      "../../../../../supabase/migrations/202610190023_hybrid_search.sql",
    );
    expect(migration).toContain("p_query_embedding real[]");
    expect(MERGED_SEARCH_AVAILABLE).toBe(true);
  });
});

describe("model input formats", () => {
  it("wraps a query in the retrieval instruction", () => {
    expect(formatQueryForModel("a $& query")).toBe(
      `Instruct: ${model.queryInstruction}\nQuery:a $& query`,
    );
  });

  it("puts the title above each chunk when there is one", () => {
    expect(formatDocumentForModel("Title ", "chunk")).toBe("Title\n\nchunk");
    expect(formatDocumentForModel(null, "chunk")).toBe("chunk");
    expect(formatDocumentForModel("  ", "chunk")).toBe("chunk");
  });

  it("uses meaning only for queries that can gain from it", () => {
    expect(queryUsesMeaning("climbing gym")).toBe(true);
    expect(queryUsesMeaning("好友")).toBe(true);
    expect(queryUsesMeaning("a")).toBe(false);
    expect(queryUsesMeaning("  好 ")).toBe(false);
    expect(queryUsesMeaning('"climbing gym"')).toBe(false);
    expect(queryUsesMeaning('"unclosed')).toBe(true);
  });
});
