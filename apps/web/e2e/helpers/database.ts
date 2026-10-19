import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

/**
 * The local Supabase database container is named after the project id in supabase/config.toml.
 * `SUPABASE_DB_CONTAINER` overrides it for a differently named stack.
 */
export function databaseContainer() {
  const override = process.env.SUPABASE_DB_CONTAINER?.trim();
  if (override) return override;
  const config = readFileSync(
    resolve(__dirname, "../../../../supabase/config.toml"),
    "utf8",
  );
  const projectId = config.match(/^project_id\s*=\s*"([^"]+)"/m)?.[1];
  if (!projectId) throw new Error("supabase/config.toml has no project_id.");
  return `supabase_db_${projectId}`;
}

/** Runs one SQL statement as the local postgres role and returns its trimmed output. */
export function sql(statement: string) {
  return execFileSync(
    "docker",
    [
      "exec",
      databaseContainer(),
      "psql",
      "-U",
      "postgres",
      "-d",
      "postgres",
      "-Atc",
      statement,
    ],
    { encoding: "utf8" },
  ).trim();
}
