import { defineConfig } from "@playwright/test";
import { e2eURL } from "./scripts/e2e-runtime.mjs";

// The gallery is deliberately absent from production builds.
export default defineConfig({
  testDir: "./e2e",
  testMatch: "**/design-system.e2e.ts",
  workers: 1,
  timeout: 60_000,
  outputDir: "./test-results/design",
  use: { baseURL: e2eURL, channel: "chrome", trace: "off" },
  webServer: {
    command: "node scripts/e2e-server.mjs",
    env: { MEMOTRAIL_E2E_PRODUCTION: "0" },
    url: `${e2eURL}/api/health`,
    reuseExistingServer: false,
    timeout: 120_000,
  },
});
