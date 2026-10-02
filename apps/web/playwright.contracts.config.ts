import { defineConfig } from "@playwright/test";

// These exercise local Supabase RPCs, Storage, and real database concurrency.
// They need neither a Next.js server nor a browser.
export default defineConfig({
  testDir: "./contracts",
  testMatch: "**/*.contract.ts",
  workers: 1,
  timeout: 60_000,
  outputDir: "./test-results/contracts",
});
