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
  if (
    relative.startsWith(`components${path.sep}`) &&
    /\.tsx?$/.test(relative)
  ) {
    const code = readFileSync(path.join(source, relative), "utf8");
    for (const match of code.matchAll(
      /from\s+["']([^"']+\.module\.css)["']/g,
    )) {
      const target = match[1].startsWith("@/")
        ? path.join(source, match[1].slice(2))
        : path.resolve(source, path.dirname(relative), match[1]);
      if (target.startsWith(path.join(source, "app") + path.sep)) {
        failures.push(
          `${relative}: components must own their CSS, not import ${match[1]}`,
        );
      }
    }
  }
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
  console.log("Web CSS uses defined tokens and component-owned styles.");
}
