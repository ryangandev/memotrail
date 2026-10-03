import { execFileSync, spawn } from "node:child_process";
import { randomUUID } from "node:crypto";

const pgArgs = [
  "exec",
  "-i",
  "supabase_db_memotrail",
  "psql",
  "-U",
  "postgres",
  "-d",
  "postgres",
  "-qAt",
  "-v",
  "ON_ERROR_STOP=1",
];

export function query(sql: string) {
  return execFileSync(
    "docker",
    [...pgArgs.filter((v) => v !== "-i"), "-c", sql],
    { encoding: "utf8" },
  ).trim();
}

/** One local psql session whose open transaction can hold locks across awaits. */
export function transaction() {
  const child = spawn("docker", pgArgs, { stdio: ["pipe", "pipe", "pipe"] });
  const done = new Promise<number | null>((resolve) =>
    child.once("exit", resolve),
  );
  child.stderr.resume();
  return {
    async run(sql: string) {
      const marker = randomUUID();
      await new Promise<void>((resolve, reject) => {
        let output = "";
        const finish = (error?: Error) => {
          clearTimeout(timer);
          child.stdout.off("data", onData);
          child.off("exit", onExit);
          if (error) reject(error);
          else resolve();
        };
        const onData = (chunk: Buffer) => {
          output += chunk.toString();
          if (output.includes(marker)) finish();
        };
        const onExit = () =>
          finish(new Error("Local SQL transaction exited unexpectedly"));
        const timer = setTimeout(
          () => finish(new Error("Local SQL barrier timed out")),
          15_000,
        );
        child.stdout.on("data", onData);
        child.once("exit", onExit);
        child.stdin.write(`${sql}\nselect '${marker}';\n`);
      });
    },
    async close() {
      child.stdin.end("rollback;\n\\q\n");
      await done;
    },
  };
}
