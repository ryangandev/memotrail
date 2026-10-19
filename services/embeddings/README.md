# MemoTrail embedding service

This directory defines the container that powers search by meaning.
It runs Hugging Face Text Embeddings Inference (CPU) with MemoTrail's own copy of the embedding model baked into the image.
It only turns text into vectors, holds no database credentials, and sends nothing to an AI provider.

The model, revision, and vector size live in one file, `apps/web/src/lib/search/semantic-model.json`.
The `Dockerfile` repeats the model and revision, and a Web unit test fails if they disagree.
Nothing here is deployed yet.

## Build and run locally

```sh
docker build -t memotrail-embeddings services/embeddings
docker run --rm -p 8080:8080 -e API_KEY=local-test-key memotrail-embeddings
```

The build downloads the pinned model once (about 1.2 GB).
Check the three routes the Web app relies on:

```sh
curl localhost:8080/health
curl -H "Authorization: Bearer local-test-key" localhost:8080/info
curl -H "Authorization: Bearer local-test-key" -H "Content-Type: application/json" \
  -d '{"input":["a note about climbing"],"model":"x"}' localhost:8080/v1/embeddings
```

The `/v1/embeddings` response should name the served model, which must equal `SEMANTIC_MODEL` in the Web app (`Qwen/Qwen3-Embedding-0.6B@97b0c614be4d`).
If it names something else, adjust `--served-model-name` before deploying, because the Web app refuses vectors from a differently named model.

## Try it from the Web app

```sh
SEMANTIC_SEARCH_URL=http://localhost:8080 SEMANTIC_SEARCH_API_KEY=local-test-key pnpm --filter @memotrail/web dev
```

Without these two variables the Web app searches by keywords only.
For tests, `apps/web/scripts/fake-embedding-server.mjs` is a deterministic stand-in that needs no model.

## Compare models

`apps/web/scripts/semantic-eval.mjs` scores candidate models on a synthetic English, Chinese, mixed, and cross-language fixture, and suggests the similarity floor for `semantic-model.json`.
Run each candidate model in its own TEI container, then:

```sh
node apps/web/scripts/semantic-eval.mjs --current http://localhost:8081 --harrier http://localhost:8082 --key local-test-key
```

The fixture marks a Chinese Entry and its English twin as separate Entries, so a twin that ranks high for a query aimed at the other one counts as an irrelevant pair in the similarity summary.
Read the floor suggestion with that in mind.

## Deploy (needs the owner's approval)

```sh
fly apps create memotrail-embeddings
fly secrets set API_KEY="$(openssl rand -hex 32)" -a memotrail-embeddings
fly deploy -c services/embeddings/fly.toml services/embeddings
```

Then set the server-only Vercel Production variables `SEMANTIC_SEARCH_URL` (`https://memotrail-embeddings.fly.dev`) and `SEMANTIC_SEARCH_API_KEY` (the same value as the Fly secret).
Leave both unset in Preview and local development.
Upgrade the machine to `performance-2x` only if p95 query embedding exceeds 300 ms.
