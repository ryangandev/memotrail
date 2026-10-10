import { defineConfig, devices } from "@playwright/test";

// Renders every exported Claude Design preview card in Chromium. Run it with
// `pnpm design-system:test:previews`, which exports a fresh copy first.
export default defineConfig({
  testDir: "./scripts/claude-design",
  testMatch: "*.e2e.mjs",
  fullyParallel: true,
  forbidOnly: Boolean(process.env.CI),
  reporter: [["list"]],
  outputDir: "./dist/claude-design/test-results",
  use: { ...devices["Desktop Chrome"] },
});
