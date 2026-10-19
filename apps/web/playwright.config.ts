import { defineConfig } from "@playwright/test";
import { e2eURL, e2eWorkers } from "./scripts/e2e-runtime.mjs";

export default defineConfig({
  testDir: "./e2e",
  testMatch: "**/*.e2e.ts",
  // The gallery needs the development server, and the semantic suite needs a fake
  // embedding service; each has its own configuration.
  testIgnore: ["**/design-system.e2e.ts", "**/semantic-search.e2e.ts"],
  // Each scenario signs in as its own disposable account, so files run in parallel.
  workers: e2eWorkers,
  timeout: 60_000,
  outputDir: "./test-results/product",
  use: { baseURL: e2eURL, channel: "chrome", trace: "off" },
  webServer: {
    command: "node scripts/e2e-server.mjs",
    url: `${e2eURL}/api/health`,
    reuseExistingServer: false,
    // A production run builds first, which takes minutes on a two-vCPU runner.
    timeout: 600_000,
  },
});
