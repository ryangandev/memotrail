import { defineConfig } from "@playwright/test";
import { e2eURL } from "./scripts/e2e-runtime.mjs";

export default defineConfig({
  testDir: "./e2e",
  testMatch: "**/*.e2e.ts",
  testIgnore: "**/design-system.e2e.ts",
  workers: 1,
  timeout: 60_000,
  outputDir: "./test-results/product",
  use: { baseURL: e2eURL, channel: "chrome", trace: "off" },
  webServer: {
    command: "node scripts/e2e-server.mjs",
    url: `${e2eURL}/api/health`,
    reuseExistingServer: false,
    timeout: 120_000,
  },
});
