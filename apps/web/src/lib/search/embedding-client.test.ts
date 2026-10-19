import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));

import {
  embedDocuments,
  embedQuery,
  readServiceConfig,
  resetEmbeddingClientState,
} from "./embedding-client";
import { SEMANTIC_DIMENSIONS, SEMANTIC_MODEL } from "./semantic-config";

const fetchMock = vi.fn();

function vectorOf(hot: number, scale = 1) {
  return Array.from({ length: SEMANTIC_DIMENSIONS }, (_, at) =>
    at === hot ? scale : 0,
  );
}

function ok(vectors: number[][], model: string | undefined = SEMANTIC_MODEL) {
  return new Response(
    JSON.stringify({
      data: vectors.map((embedding, index) => ({ embedding, index })),
      ...(model === undefined ? {} : { model }),
    }),
    { status: 200 },
  );
}

beforeEach(() => {
  vi.stubGlobal("fetch", fetchMock);
  vi.stubEnv("SEMANTIC_SEARCH_URL", "https://embeddings.example.test/");
  vi.stubEnv("SEMANTIC_SEARCH_API_KEY", "secret-key");
  vi.spyOn(console, "warn").mockImplementation(() => undefined);
  resetEmbeddingClientState();
});

afterEach(() => {
  fetchMock.mockReset();
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
  vi.useRealTimers();
});

describe("readServiceConfig", () => {
  const read = (url?: string, key?: string) =>
    readServiceConfig({
      SEMANTIC_SEARCH_API_KEY: key,
      SEMANTIC_SEARCH_URL: url,
    });

  it("needs both a URL and a key", () => {
    expect(read("https://e.test", "k")).toEqual({
      apiKey: "k",
      baseUrl: "https://e.test",
    });
    expect(read("https://e.test", "")).toBeNull();
    expect(read(undefined, "k")).toBeNull();
  });

  it("accepts HTTPS and loopback HTTP only", () => {
    expect(read("http://127.0.0.1:8788", "k")).not.toBeNull();
    expect(read("http://localhost:8788", "k")).not.toBeNull();
    expect(read("http://embeddings.example.test", "k")).toBeNull();
    expect(read("not a url", "k")).toBeNull();
  });
});

describe("embedQuery", () => {
  it("is unavailable without configuration and never calls the network", async () => {
    vi.stubEnv("SEMANTIC_SEARCH_URL", "");

    expect(await embedQuery("bikes", { timeoutMs: 100 })).toEqual({
      reason: "not_configured",
      status: "unavailable",
    });
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("sends the instructed query with the bearer key and normalizes the vector", async () => {
    fetchMock.mockResolvedValueOnce(ok([vectorOf(3, 5)]));

    const result = await embedQuery("the guy who fixed bikes", {
      timeoutMs: 500,
    });

    expect(result.status).toBe("ok");
    if (result.status === "ok") {
      expect(result.vector[3]).toBeCloseTo(1, 9);
      expect(Math.hypot(...result.vector)).toBeCloseTo(1, 9);
    }
    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe("https://embeddings.example.test/v1/embeddings");
    expect(init.headers.Authorization).toBe("Bearer secret-key");
    const body = JSON.parse(init.body);
    expect(body.model).toBe(SEMANTIC_MODEL);
    expect(body.input).toHaveLength(1);
    expect(body.input[0]).toMatch(
      /^Instruct: .+\nQuery:the guy who fixed bikes$/,
    );
  });

  it("answers a repeated query from memory", async () => {
    fetchMock.mockResolvedValue(ok([vectorOf(1)]));

    await embedQuery("same words", { timeoutMs: 500 });
    await embedQuery("same words", { timeoutMs: 500 });
    await embedQuery("other words", { timeoutMs: 500 });

    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("forgets a cached query after ten minutes", async () => {
    vi.useFakeTimers();
    fetchMock.mockResolvedValue(ok([vectorOf(1)]));

    await embedQuery("same words", { timeoutMs: 500 });
    vi.advanceTimersByTime(10 * 60_000 + 1);
    await embedQuery("same words", { timeoutMs: 500 });

    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it.each([
    ["a server error", () => new Response("", { status: 503 }), "unavailable"],
    ["a wrong key", () => new Response("", { status: 401 }), "unavailable"],
    ["a rate limit", () => new Response("", { status: 429 }), "unavailable"],
    [
      "invalid JSON",
      () => new Response("<html>", { status: 200 }),
      "bad_response",
    ],
    ["a wrong dimension", () => ok([[1, 2, 3]]), "bad_response"],
    [
      "a non-finite value",
      () =>
        ok([
          vectorOf(0).map((value, at) => (at === 5 ? null : value)) as number[],
        ]),
      "bad_response",
    ],
    ["a zero vector", () => ok([vectorOf(0, 0)]), "bad_response"],
    [
      "the wrong number of vectors",
      () => ok([vectorOf(0), vectorOf(1)]),
      "bad_response",
    ],
    [
      "another model",
      () => ok([vectorOf(0)], "someone/else-model@123456789abc"),
      "model_mismatch",
    ],
  ])("is unavailable on %s", async (_name, respond, reason) => {
    fetchMock.mockResolvedValueOnce(respond());

    expect(await embedQuery("bikes", { timeoutMs: 500 })).toEqual({
      reason,
      status: "unavailable",
    });
  });

  it("accepts a service that does not name its model", async () => {
    fetchMock.mockResolvedValueOnce(ok([vectorOf(2)], undefined));
    expect((await embedQuery("bikes", { timeoutMs: 500 })).status).toBe("ok");
  });

  it("becomes unavailable on a timeout, then skips the service for thirty seconds", async () => {
    vi.useFakeTimers();
    fetchMock.mockRejectedValueOnce(
      Object.assign(new Error("timed out"), { name: "TimeoutError" }),
    );

    expect(await embedQuery("first", { timeoutMs: 10 })).toEqual({
      reason: "timeout",
      status: "unavailable",
    });
    expect(await embedQuery("second", { timeoutMs: 10 })).toEqual({
      reason: "unavailable",
      status: "unavailable",
    });
    expect(fetchMock).toHaveBeenCalledTimes(1);

    vi.advanceTimersByTime(30_001);
    fetchMock.mockResolvedValueOnce(ok([vectorOf(1)]));
    expect((await embedQuery("third", { timeoutMs: 10 })).status).toBe("ok");
  });

  it("never logs the query text", async () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => undefined);
    fetchMock.mockRejectedValueOnce(
      new Error("connect failed for secret words"),
    );

    await embedQuery("secret words", { timeoutMs: 10 });

    expect(warn).toHaveBeenCalledWith("[semantic-search] unavailable");
    expect(JSON.stringify(warn.mock.calls)).not.toContain("secret words");
  });
});

describe("embedDocuments", () => {
  it("sends documents without a query instruction, in batches of eight", async () => {
    const texts = Array.from({ length: 11 }, (_, at) => `passage ${at}`);
    fetchMock.mockImplementation(async (_url, init) =>
      ok(
        JSON.parse(init.body).input.map((_: string, at: number) =>
          vectorOf(at),
        ),
      ),
    );

    const result = await embedDocuments(texts);

    expect(result.status).toBe("ok");
    if (result.status === "ok") expect(result.vectors).toHaveLength(11);
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(JSON.parse(fetchMock.mock.calls[0][1].body).input).toEqual(
      texts.slice(0, 8),
    );
  });

  it("reports input the service refuses as rejected, without opening the breaker", async () => {
    fetchMock.mockResolvedValueOnce(new Response("", { status: 422 }));
    expect(await embedDocuments(["too strange"])).toEqual({
      reason: "input_rejected",
      status: "rejected",
    });

    fetchMock.mockResolvedValueOnce(ok([vectorOf(0)]));
    expect((await embedDocuments(["fine"])).status).toBe("ok");
  });

  it("stops at the first unavailable batch", async () => {
    fetchMock.mockResolvedValueOnce(new Response("", { status: 500 }));

    const result = await embedDocuments(
      Array.from({ length: 20 }, () => "text"),
    );

    expect(result).toEqual({ reason: "unavailable", status: "unavailable" });
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });
});
