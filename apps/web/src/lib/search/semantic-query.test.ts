import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));
const state = vi.hoisted(() => ({ merged: true }));
vi.mock("./semantic-config", async (importOriginal) => ({
  ...(await importOriginal<typeof import("./semantic-config")>()),
  get MERGED_SEARCH_AVAILABLE() {
    return state.merged;
  },
}));
const embedQuery = vi.hoisted(() => vi.fn());
const configured = vi.hoisted(() => vi.fn(() => true));
vi.mock("./embedding-client", () => ({
  embedQuery,
  semanticSearchConfigured: configured,
}));
const schedule = vi.hoisted(() => vi.fn());
vi.mock("./search-index", () => ({ scheduleSearchIndexDrain: schedule }));

import { SEMANTIC_MIN_SIMILARITY, SEMANTIC_MODEL } from "./semantic-config";
import { prepareSemanticSearch } from "./semantic-query";
import type { SearchIndexClient } from "./search-index";

function clientWith(result: {
  data: unknown;
  error: { message: string } | null;
}) {
  const rpc = vi.fn(async () => result);
  return { client: { rpc } as unknown as SearchIndexClient, rpc };
}

const indexed = (enabled: boolean, pending: number) =>
  clientWith({ data: [{ enabled, pending }], error: null });

beforeEach(() => {
  state.merged = true;
  configured.mockReturnValue(true);
  embedQuery.mockReset();
  schedule.mockReset();
});

describe("prepareSemanticSearch", () => {
  it("stays keyword-only, silently, without an embedding service", async () => {
    configured.mockReturnValue(false);
    const { client, rpc } = indexed(true, 0);

    const prepared = await prepareSemanticSearch(
      client,
      "u",
      "bikes",
      "library",
    );

    expect(prepared).toEqual({
      arguments: null,
      status: { pendingCount: 0, state: "not_configured" },
    });
    expect(rpc).not.toHaveBeenCalled();
    expect(embedQuery).not.toHaveBeenCalled();
  });

  it("stays keyword-only when the database predates the index functions", async () => {
    const { client } = clientWith({
      data: null,
      error: { message: "missing" },
    });

    const prepared = await prepareSemanticSearch(
      client,
      "u",
      "bikes",
      "library",
    );

    expect(prepared.status.state).toBe("not_configured");
    expect(prepared.arguments).toBeNull();
    expect(embedQuery).not.toHaveBeenCalled();
  });

  it("sends nothing to the model when the user turned the setting off", async () => {
    const { client } = indexed(false, 0);

    const prepared = await prepareSemanticSearch(
      client,
      "u",
      "bikes",
      "library",
    );

    expect(prepared).toEqual({
      arguments: null,
      status: { pendingCount: 0, state: "off" },
    });
    expect(embedQuery).not.toHaveBeenCalled();
    expect(schedule).not.toHaveBeenCalled();
  });

  it("passes the query vector, model, and floor to the search function", async () => {
    embedQuery.mockResolvedValue({ status: "ok", vector: [0.5, 0.5] });
    const { client } = indexed(true, 0);

    const prepared = await prepareSemanticSearch(client, "u", "bikes", "quick");

    expect(embedQuery).toHaveBeenCalledWith("bikes", { timeoutMs: 600 });
    expect(prepared).toEqual({
      arguments: {
        p_embedding_model: SEMANTIC_MODEL,
        p_query_embedding: [0.5, 0.5],
        p_semantic_min_similarity: SEMANTIC_MIN_SIMILARITY,
      },
      status: { pendingCount: 0, state: "on" },
    });
  });

  it("falls back to keywords and says so when the service does not answer", async () => {
    embedQuery.mockResolvedValue({ reason: "timeout", status: "unavailable" });
    const { client } = indexed(true, 3);

    const prepared = await prepareSemanticSearch(
      client,
      "u",
      "bikes",
      "library",
    );

    expect(embedQuery).toHaveBeenCalledWith("bikes", { timeoutMs: 1200 });
    expect(prepared).toEqual({
      arguments: null,
      status: { pendingCount: 3, state: "unavailable" },
    });
  });

  it("skips the model for one-character queries and quoted phrases", async () => {
    const { client } = indexed(true, 0);

    for (const query of ["a", "好", '"exact phrase"']) {
      const prepared = await prepareSemanticSearch(
        client,
        "u",
        query,
        "library",
      );
      expect(prepared.arguments).toBeNull();
      expect(prepared.status.state).toBe("on");
    }
    expect(embedQuery).not.toHaveBeenCalled();
  });

  it("schedules indexing when Entries are waiting", async () => {
    embedQuery.mockResolvedValue({ status: "ok", vector: [1] });
    const { client } = indexed(true, 2);

    await prepareSemanticSearch(client, "u", "bikes", "library");

    expect(schedule).toHaveBeenCalledWith(client, "u");
  });

  it("keeps indexing but sends no vector until the merged search is deployed", async () => {
    state.merged = false;
    const { client } = indexed(true, 5);

    const prepared = await prepareSemanticSearch(
      client,
      "u",
      "bikes",
      "library",
    );

    expect(schedule).toHaveBeenCalledTimes(1);
    expect(embedQuery).not.toHaveBeenCalled();
    expect(prepared).toEqual({
      arguments: null,
      status: { pendingCount: 0, state: "not_configured" },
    });
  });
});
