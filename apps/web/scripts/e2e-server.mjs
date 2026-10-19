import { execFileSync, spawn } from "node:child_process";
import { writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { createFakeAIProvider } from "./fake-ai-provider.mjs";
import { e2ePort, e2eURL } from "./e2e-runtime.mjs";

const local = JSON.parse(
  execFileSync("supabase", ["status", "-o", "json"], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
  }),
);
// Any local stack will do, including a second one on other ports for concurrent work.
if (!/^http:\/\/127\.0\.0\.1:\d+$/.test(local.API_URL))
  throw new Error("E2E requires the local Supabase instance.");
const distDir = process.env.MEMOTRAIL_NEXT_DIST_DIR || `.next-e2e-${e2ePort}`;
const tsconfig = `tsconfig.e2e-${e2ePort}.json`;
// Next adds generated type paths to its configured file. Keep test paths out of the
// tracked editor configuration, including when independent ports run concurrently.
writeFileSync(
  tsconfig,
  JSON.stringify({
    extends: "./tsconfig.json",
    include: [
      "next-env.d.ts",
      "**/*.ts",
      "**/*.tsx",
      "**/*.mts",
      `${distDir}/types/**/*.ts`,
      `${distDir}/dev/types/**/*.ts`,
    ],
    exclude: ["node_modules"],
  }),
);
// Reviews and Chapter suggestions run against a scripted provider unless a live run is asked
// for, so no test reaches the network or spends money. Tests read it on `e2ePort + 2000`.
const liveAI = process.env.MEMOTRAIL_E2E_LIVE_AI === "1";
const fakeAIKey = "synthetic-e2e-key";
let fakeAI = null;
if (!liveAI) {
  fakeAI = createFakeAIProvider({ apiKey: fakeAIKey });
  await fakeAI.start(e2ePort + 2000);
}
const env = {
  ...process.env,
  MEMOTRAIL_NEXT_DIST_DIR: distDir,
  MEMOTRAIL_NEXT_TSCONFIG: tsconfig,
  NEXT_PUBLIC_APP_URL: e2eURL,
  NEXT_PUBLIC_SUPABASE_URL: local.API_URL,
  NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: local.PUBLISHABLE_KEY || local.ANON_KEY,
  SUPABASE_SECRET_KEY: local.SECRET_KEY || local.SERVICE_ROLE_KEY,
  GEOAPIFY_API_KEY:
    process.env.MEMOTRAIL_E2E_LIVE_GEOAPIFY === "1"
      ? process.env.GEOAPIFY_API_KEY
      : "",
  // Search by meaning is off unless the semantic suite names its fake embedding service,
  // so a developer's own SEMANTIC_SEARCH_* settings never reach browser tests.
  SEMANTIC_SEARCH_URL: process.env.MEMOTRAIL_E2E_SEMANTIC_URL ?? "",
  SEMANTIC_SEARCH_API_KEY: process.env.MEMOTRAIL_E2E_SEMANTIC_KEY ?? "",
  // Real provider testing is explicit, bounded, and still uses synthetic local records.
  AI_PROVIDER: "anthropic",
  ...(liveAI
    ? {}
    : {
        AI_API_KEY: fakeAIKey,
        AI_API_BASE_URL: `http://127.0.0.1:${e2ePort + 2000}`,
      }),
  // One review holds about $0.19 while it runs, and an interrupted one keeps it, so the
  // server allowance has to cover every account a run creates. Each account keeps the default.
  AI_MONTHLY_BUDGET_USD: "25",
};
const production = process.env.MEMOTRAIL_E2E_PRODUCTION === "1";
// Build with the same local-only public configuration that next start will serve.
if (production)
  execFileSync("pnpm", ["exec", "next", "build"], { env, stdio: "inherit" });
const server = spawn(
  process.execPath,
  [
    fileURLToPath(import.meta.resolve("next/dist/bin/next")),
    production ? "start" : "dev",
    "--hostname",
    "127.0.0.1",
    "--port",
    String(e2ePort),
  ],
  { stdio: "inherit", env },
);
for (const signal of ["SIGINT", "SIGTERM"])
  process.on(signal, () => server.kill(signal));
server.on("exit", async (code) => {
  await fakeAI?.stop();
  process.exit(code ?? 1);
});
