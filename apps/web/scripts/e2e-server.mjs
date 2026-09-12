import { execFileSync, spawn } from "node:child_process";

const local = JSON.parse(
  execFileSync("supabase", ["status", "-o", "json"], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
  }),
);
if (local.API_URL !== "http://127.0.0.1:54321")
  throw new Error("E2E requires the local Supabase instance.");
const server = spawn(
  "pnpm",
  ["exec", "next", "dev", "--hostname", "127.0.0.1", "--port", "3100"],
  {
    stdio: "inherit",
    env: {
      ...process.env,
      NEXT_PUBLIC_APP_URL: "http://127.0.0.1:3100",
      NEXT_PUBLIC_SUPABASE_URL: local.API_URL,
      NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY:
        local.PUBLISHABLE_KEY || local.ANON_KEY,
      SUPABASE_SECRET_KEY: local.SECRET_KEY || local.SERVICE_ROLE_KEY,
      // Real provider testing is explicit, bounded, and still uses synthetic local records.
      AI_PROVIDER:
        process.env.MEMOTRAIL_E2E_LIVE_AI === "1" ? "anthropic" : "disabled",
      AI_TOTAL_BUDGET_USD: "0.10",
    },
  },
);
for (const signal of ["SIGINT", "SIGTERM"])
  process.on(signal, () => server.kill(signal));
server.on("exit", (code) => process.exit(code ?? 1));
