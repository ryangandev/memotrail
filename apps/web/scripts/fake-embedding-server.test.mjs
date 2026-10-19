import { afterAll, beforeAll, describe, expect, it } from "vitest";
import {
  FAKE_MODEL_NAME,
  OUTAGE_SENTINEL,
  createFakeEmbeddingServer,
  fakeEmbed,
} from "./fake-embedding-server.mjs";
import { cosine } from "./semantic-eval-lib.mjs";

describe("fakeEmbed", () => {
  it("is deterministic and returns unit vectors of the configured size", () => {
    const first = fakeEmbed("Met a guy at the climbing gym");
    expect(fakeEmbed("Met a guy at the climbing gym")).toEqual(first);
    expect(first).toHaveLength(1024);
    expect(Math.hypot(...first)).toBeCloseTo(1, 6);
  });

  it("puts English and Chinese synonyms close together", () => {
    const english = fakeEmbed("the guy at the climbing gym who fixes bikes");
    const chinese = fakeEmbed("在攀岩馆认识了一个会修自行车的人");
    const unrelated = fakeEmbed(
      "Paid the electricity bill and renewed the internet plan",
    );

    expect(cosine(english, chinese)).toBeGreaterThan(0.7);
    expect(cosine(english, unrelated)).toBeLessThan(0.2);
  });

  it("ignores the retrieval instruction a query carries", () => {
    const bare = fakeEmbed("grandma dumplings");
    const wrapped = fakeEmbed(
      "Instruct: Given a short or vague description, retrieve the entry\nQuery:grandma dumplings",
    );
    expect(cosine(bare, wrapped)).toBeCloseTo(1, 6);
  });

  it("still returns a valid unit vector for text it knows nothing about", () => {
    expect(Math.hypot(...fakeEmbed("..."))).toBeCloseTo(1, 6);
    expect(Math.hypot(...fakeEmbed(""))).toBeCloseTo(1, 6);
  });
});

describe("the fake embedding server", () => {
  const fake = createFakeEmbeddingServer({ apiKey: "test-key" });
  let url = "";

  beforeAll(async () => {
    url = await fake.start();
  });
  afterAll(() => fake.stop());

  const post = (body, key = "test-key") =>
    fetch(`${url}/v1/embeddings`, {
      body: JSON.stringify(body),
      headers: {
        Authorization: `Bearer ${key}`,
        "Content-Type": "application/json",
      },
      method: "POST",
    });

  it("answers the OpenAI-compatible route with the served model name", async () => {
    const response = await post({ input: ["one", "two"], model: "ignored" });
    const payload = await response.json();

    expect(response.status).toBe(200);
    expect(payload.model).toBe(FAKE_MODEL_NAME);
    expect(payload.data.map((item) => item.index)).toEqual([0, 1]);
    expect(payload.data[0].embedding).toHaveLength(1024);
  });

  it("reports health and the model", async () => {
    expect((await fetch(`${url}/health`)).status).toBe(200);
    expect(await (await fetch(`${url}/info`)).json()).toEqual({
      model_id: FAKE_MODEL_NAME,
    });
  });

  it("requires the API key", async () => {
    expect((await post({ input: ["x"] }, "wrong")).status).toBe(401);
  });

  it("answers 503 for the outage sentinel", async () => {
    const response = await post({ input: [`a ${OUTAGE_SENTINEL} b`] });
    expect(response.status).toBe(503);
  });

  it("rejects input that is not text", async () => {
    expect((await post({ input: [3] })).status).toBe(422);
  });
});
