import { defineConfig } from "@playwright/test";
import {
  e2eEmbeddingKey,
  e2eEmbeddingPort,
  e2eEmbeddingURL,
  e2eURL,
} from "./scripts/e2e-runtime.mjs";

// Search by meaning needs an embedding service. This suite starts the deterministic fake
// beside its own app server; the main product suite stays keyword-only.
export default defineConfig({
  testDir: "./e2e",
  testMatch: "**/semantic-search.e2e.ts",
  workers: 1,
  timeout: 90_000,
  outputDir: "./test-results/semantic",
  use: { baseURL: e2eURL, channel: "chrome", trace: "off" },
  webServer: [
    {
      command: `node scripts/fake-embedding-server.mjs ${e2eEmbeddingPort} ${e2eEmbeddingKey}`,
      url: `${e2eEmbeddingURL}/health`,
      reuseExistingServer: false,
      timeout: 30_000,
    },
    {
      command: "node scripts/e2e-server.mjs",
      env: {
        MEMOTRAIL_E2E_PRODUCTION: "0",
        MEMOTRAIL_E2E_SEMANTIC_KEY: e2eEmbeddingKey,
        MEMOTRAIL_E2E_SEMANTIC_URL: e2eEmbeddingURL,
      },
      url: `${e2eURL}/api/health`,
      reuseExistingServer: false,
      timeout: 120_000,
    },
  ],
});
