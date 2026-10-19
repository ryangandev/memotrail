import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));
const afterCallbacks = vi.hoisted(() => [] as Array<() => Promise<void>>);
vi.mock("next/server", () => ({
  after: (callback: () => Promise<void>) => afterCallbacks.push(callback),
}));

import { SEMANTIC_DIMENSIONS, SEMANTIC_MODEL } from "./semantic-config";
import {
  drainSearchIndex,
  scheduleSearchIndexDrain,
  type SearchIndexClient,
} from "./search-index";

const vector = Array.from({ length: SEMANTIC_DIMENSIONS }, (_, at) =>
  at === 0 ? 1 : 0,
);
const hash = "a".repeat(64);

function job(id: string, body = "A short note.", title: string | null = null) {
  return { body, entry_id: id, source_hash: hash, title };
}

/** A client that hands out the queued batches of jobs, one per claim. */
function clientWith(
  batches: unknown[][],
  responses: Partial<Record<string, unknown>> = {},
) {
  const queue = [...batches];
  const rpc = vi.fn(async (name: string) => {
    if (name === "claim_entry_search_index_jobs") {
      return { data: queue.shift() ?? [], error: null };
    }
    if (name in responses) return responses[name] as never;
    return { data: true, error: null };
  });
  return { client: { rpc } as unknown as SearchIndexClient, rpc };
}

const embedder = () =>
  vi.fn(async (texts: readonly string[]) => ({
    status: "ok" as const,
    vectors: texts.map(() => vector),
  }));

const calls = (rpc: ReturnType<typeof vi.fn>, name: string) =>
  rpc.mock.calls.filter(([called]) => called === name);

beforeEach(() => {
  afterCallbacks.length = 0;
  vi.unstubAllEnvs();
});

describe("drainSearchIndex", () => {
  it("claims, embeds, and stores until nothing is left", async () => {
    const { client, rpc } = clientWith([
      [job("a"), job("b", "Body", "Title")],
      [job("c")],
    ]);
    const embed = embedder();

    const result = await drainSearchIndex(client, "owner-1", { embed });

    expect(result).toEqual({
      indexed: 3,
      rejected: 0,
      stale: 0,
      stoppedBecause: "idle",
    });
    expect(calls(rpc, "claim_entry_search_index_jobs")[0][1]).toEqual({
      p_limit: 4,
      p_model: SEMANTIC_MODEL,
    });
    const stored = calls(rpc, "store_entry_search_chunks");
    expect(stored).toHaveLength(3);
    expect(stored[1][1]).toMatchObject({
      p_entry_id: "b",
      p_model: SEMANTIC_MODEL,
      p_source_hash: hash,
    });
    expect(stored[1][1].p_chunks).toEqual([
      { embedding: vector, end: 4, index: 0, start: 0 },
    ]);
    // The title gives the chunk its context in the embedded text.
    expect(embed.mock.calls[1][0]).toEqual(["Title\n\nBody"]);
  });

  it("stores an Entry with no text as zero chunks", async () => {
    const { client, rpc } = clientWith([[job("blank", "  ", null)]]);

    await drainSearchIndex(client, "owner-1", { embed: embedder() });

    expect(calls(rpc, "store_entry_search_chunks")[0][1].p_chunks).toEqual([]);
  });

  it("stops on an unavailable service without recording a failure", async () => {
    const { client, rpc } = clientWith([[job("a"), job("b")]]);
    const embed = vi.fn(async () => ({
      reason: "timeout" as const,
      status: "unavailable" as const,
    }));

    const result = await drainSearchIndex(client, "owner-1", { embed });

    expect(result.stoppedBecause).toBe("unavailable");
    expect(embed).toHaveBeenCalledTimes(1);
    expect(calls(rpc, "fail_entry_search_index_job")).toHaveLength(0);
    expect(calls(rpc, "store_entry_search_chunks")).toHaveLength(0);
  });

  it("records a failure when the service rejects one Entry and keeps going", async () => {
    const { client, rpc } = clientWith([[job("bad"), job("good")]]);
    const embed = vi
      .fn()
      .mockResolvedValueOnce({ reason: "input_rejected", status: "rejected" })
      .mockResolvedValue({ status: "ok", vectors: [vector] });

    const result = await drainSearchIndex(client, "owner-1", { embed });

    expect(result).toMatchObject({ indexed: 1, rejected: 1 });
    expect(calls(rpc, "fail_entry_search_index_job")[0][1]).toEqual({
      p_entry_id: "bad",
      p_error: "input_rejected",
      p_source_hash: hash,
    });
  });

  it("leaves an Entry that changed while it was embedded for the next drain", async () => {
    const { client } = clientWith([[job("a")]], {
      store_entry_search_chunks: { data: false, error: null },
    });

    const result = await drainSearchIndex(client, "owner-1", {
      embed: embedder(),
    });

    expect(result).toMatchObject({
      indexed: 0,
      stale: 1,
      stoppedBecause: "idle",
    });
  });

  it("stops when the budget is spent", async () => {
    let clock = 0;
    const { client } = clientWith([[job("a")], [job("b")]]);

    const result = await drainSearchIndex(client, "owner-1", {
      budgetMs: 1000,
      embed: async (texts) => {
        clock += 600;
        return { status: "ok", vectors: texts.map(() => vector) };
      },
      now: () => clock,
    });

    expect(result.stoppedBecause).toBe("budget");
    expect(result.indexed).toBe(2);
  });

  it("stops on a database error instead of looping", async () => {
    const rpc = vi.fn(async () => ({ data: null, error: { message: "boom" } }));

    const result = await drainSearchIndex(
      { rpc } as unknown as SearchIndexClient,
      "owner-1",
      {
        embed: embedder(),
      },
    );

    expect(result.stoppedBecause).toBe("error");
    expect(rpc).toHaveBeenCalledTimes(1);
  });

  it("stops when the database answers with something unexpected", async () => {
    const { client } = clientWith([[{ entry_id: 3 }]]);
    expect(
      (await drainSearchIndex(client, "owner-1", { embed: embedder() }))
        .stoppedBecause,
    ).toBe("error");
  });

  it("allows one drain per owner at a time", async () => {
    let release: () => void = () => undefined;
    const gate = new Promise<void>((resolve) => (release = resolve));
    const { client } = clientWith([[job("a")]]);
    const embed = vi.fn(async (texts: readonly string[]) => {
      await gate;
      return { status: "ok" as const, vectors: texts.map(() => vector) };
    });

    const first = drainSearchIndex(client, "owner-1", { embed });
    const second = await drainSearchIndex(client, "owner-1", { embed });
    const otherOwner = drainSearchIndex(clientWith([[]]).client, "owner-2", {
      embed,
    });

    expect(second.stoppedBecause).toBe("busy");
    expect((await otherOwner).stoppedBecause).toBe("idle");
    release();
    expect((await first).indexed).toBe(1);
    // Finished, so the owner can drain again.
    expect(
      (await drainSearchIndex(clientWith([[]]).client, "owner-1", { embed }))
        .stoppedBecause,
    ).toBe("idle");
  });
});

describe("scheduleSearchIndexDrain", () => {
  it("does nothing without an embedding service", () => {
    vi.stubEnv("SEMANTIC_SEARCH_URL", "");
    vi.stubEnv("SEMANTIC_SEARCH_API_KEY", "");

    scheduleSearchIndexDrain(clientWith([]).client, "owner-1");

    expect(afterCallbacks).toHaveLength(0);
  });

  it("drains after the response when the service is configured", async () => {
    vi.stubEnv("SEMANTIC_SEARCH_URL", "https://embeddings.example.test");
    vi.stubEnv("SEMANTIC_SEARCH_API_KEY", "key");
    const { client, rpc } = clientWith([]);

    scheduleSearchIndexDrain(client, "owner-9");
    expect(rpc).not.toHaveBeenCalled();

    await afterCallbacks[0]();
    expect(calls(rpc, "claim_entry_search_index_jobs")).toHaveLength(1);
  });
});
