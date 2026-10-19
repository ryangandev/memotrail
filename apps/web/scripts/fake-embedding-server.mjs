import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { createServer } from "node:http";
import { fileURLToPath } from "node:url";

/**
 * A deterministic stand-in for the embedding service, used by tests and local runs when
 * no real model is available. It speaks the same OpenAI-compatible route as Text
 * Embeddings Inference. Texts that share a synonym group, in English or Chinese, get
 * nearby vectors, so "bike" and "自行车" land close together; unrelated texts do not.
 * It is not a language model and is never used outside tests.
 */
const model = JSON.parse(
  readFileSync(
    fileURLToPath(
      new URL("../src/lib/search/semantic-model.json", import.meta.url),
    ),
    "utf8",
  ),
);
const lexicon = JSON.parse(
  readFileSync(
    fileURLToPath(new URL("./fake-embedding-concepts.json", import.meta.url)),
    "utf8",
  ),
).concepts;

/** A query that contains this phrase makes the server answer 503, like an outage. */
export const OUTAGE_SENTINEL = "SEMANTIC_OUTAGE_SENTINEL";
export const FAKE_MODEL_NAME = `${model.huggingFaceId}@${model.revision.slice(0, 12)}`;

const CONCEPT_DIMENSIONS = 128;
const hasHan = /[⺀-鿿]/u;
const conceptNames = Object.keys(lexicon);

if (conceptNames.length > CONCEPT_DIMENSIONS) {
  throw new Error(
    "The fake lexicon has more concepts than reserved dimensions.",
  );
}

export function fakeEmbed(text, dimensions = model.dimensions) {
  // Drop the retrieval instruction a query carries, which says nothing about its topic.
  const marker = text.lastIndexOf("\nQuery:");
  const content = (marker >= 0 ? text.slice(marker + "\nQuery:".length) : text)
    .toLowerCase()
    .normalize("NFKC");
  const words = new Set(content.match(/[\p{L}\p{N}']+/gu) ?? []);
  const vector = new Array(dimensions).fill(0);
  const explained = new Set();

  conceptNames.forEach((name, position) => {
    let hits = 0;
    for (const term of lexicon[name]) {
      const matches = hasHan.test(term)
        ? content.includes(term)
        : words.has(term);
      if (matches) {
        hits += 1;
        explained.add(term);
      }
    }
    if (hits > 0) vector[position] += 1 + 0.3 * Math.min(hits - 1, 2);
  });

  // Words no group knows still give each text a faint, stable fingerprint.
  const fingerprint = (token, weight) => {
    const bucket =
      CONCEPT_DIMENSIONS +
      (createHash("sha256").update(token).digest().readUInt32BE(0) %
        (dimensions - CONCEPT_DIMENSIONS));
    vector[bucket] += weight;
  };
  for (const word of words) {
    if (!explained.has(word) && !hasHan.test(word)) fingerprint(word, 0.12);
  }
  const han = Array.from(content).filter((character) => hasHan.test(character));
  for (let position = 0; position + 1 < han.length; position += 1) {
    fingerprint(han[position] + han[position + 1], 0.06);
  }

  const energy = Math.sqrt(
    vector.reduce((sum, value) => sum + value * value, 0),
  );
  // A text that says nothing still gets a valid unit vector, as a real model would.
  if (energy === 0) {
    vector[dimensions - 1] = 1;
    return vector;
  }
  return vector.map((value) => value / energy);
}

export function createFakeEmbeddingServer({
  apiKey,
  modelName = FAKE_MODEL_NAME,
} = {}) {
  const requests = [];

  const server = createServer(async (request, response) => {
    const send = (status, body) => {
      response.writeHead(status, { "Content-Type": "application/json" });
      response.end(JSON.stringify(body));
    };

    if (request.method === "GET" && request.url === "/health") {
      return send(200, { status: "ok" });
    }
    if (request.method === "GET" && request.url === "/info") {
      return send(200, { model_id: modelName });
    }
    if (request.method !== "POST" || request.url !== "/v1/embeddings") {
      return send(404, { error: "not_found" });
    }
    if (apiKey && request.headers.authorization !== `Bearer ${apiKey}`) {
      return send(401, { error: "unauthorized" });
    }

    let payload;
    try {
      const chunks = [];
      for await (const chunk of request) chunks.push(chunk);
      payload = JSON.parse(Buffer.concat(chunks).toString("utf8"));
    } catch {
      return send(400, { error: "invalid_json" });
    }

    const input = Array.isArray(payload.input)
      ? payload.input
      : [payload.input];
    if (!input.every((item) => typeof item === "string")) {
      return send(422, { error: "invalid_input" });
    }
    requests.push({ input, model: payload.model });
    if (input.some((item) => item.includes(OUTAGE_SENTINEL))) {
      return send(503, { error: "unavailable" });
    }

    return send(200, {
      data: input.map((item, index) => ({
        embedding: fakeEmbed(item),
        index,
        object: "embedding",
      })),
      model: modelName,
      object: "list",
    });
  });

  return {
    /** Every embeddings request seen so far, for assertions. */
    requests,
    async start(port = 0) {
      await new Promise((resolve) => server.listen(port, "127.0.0.1", resolve));
      return `http://127.0.0.1:${server.address().port}`;
    },
    async stop() {
      await new Promise((resolve) => server.close(resolve));
    },
  };
}

// `node scripts/fake-embedding-server.mjs [port] [api-key]` runs it by hand.
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const port = Number(process.argv[2] ?? 8788);
  const apiKey = process.argv[3] ?? "fake-embedding-key";
  const fake = createFakeEmbeddingServer({ apiKey });
  const url = await fake.start(port);
  console.log(`Fake embedding server on ${url} (Bearer ${apiKey})`);
}
