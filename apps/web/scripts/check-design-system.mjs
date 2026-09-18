import { readFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const source = fileURLToPath(new URL("../src/", import.meta.url));
const generated = readFileSync(
  path.join(source, "styles/generated-tokens.css"),
  "utf8",
);
const tokens = new Set(
  [...generated.matchAll(/(--mt-[\w-]+)\s*:/g)].map((match) => match[1]),
);
const failures = [];
for (const relative of readdirSync(source, { recursive: true })) {
  if (!relative.endsWith(".css") || relative.endsWith("generated-tokens.css"))
    continue;
  const css = readFileSync(path.join(source, relative), "utf8");
  const local = new Set(
    [...css.matchAll(/(--mt-[\w-]+)\s*:/g)].map((match) => match[1]),
  );
  for (const match of css.matchAll(/var\((--mt-[\w-]+)/g)) {
    if (!tokens.has(match[1]) && !local.has(match[1])) {
      const line = css.slice(0, match.index).split("\n").length;
      failures.push(`${relative}:${line}: undefined token ${match[1]}`);
    }
  }
}
if (failures.length) {
  console.error(failures.join("\n"));
  process.exitCode = 1;
} else {
  console.log(
    "Web CSS references only generated tokens or module-local variables.",
  );
}
