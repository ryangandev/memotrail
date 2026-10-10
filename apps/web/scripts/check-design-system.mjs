import { readFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { checkCss, checkScript, readTokens } from "./design-system-rules.mjs";

// Fails when Web source draws a visual value by hand instead of through a generated design
// token, or when a component imports route styles. The rules live in design-system-rules.mjs.

const source = fileURLToPath(new URL("../src/", import.meta.url));
const generatedCss = "styles/generated-tokens.css";
const tokens = readTokens(
  readFileSync(path.join(source, generatedCss), "utf8"),
);

// Colors a script must keep as written, with the reason.
const allowedScriptColors = {
  [path.join("components", "auth-gate.tsx")]: {
    colors: ["#4285F4", "#34A853", "#FBBC05", "#EA4335"],
    reason: "Google's sign-in mark must use Google's brand colors.",
  },
};

const findings = [];
for (const relative of readdirSync(source, { recursive: true })) {
  const file = path.join(source, relative);
  if (relative.endsWith(".css")) {
    if (relative === path.normalize(generatedCss)) continue;
    findings.push(...checkCss(relative, readFileSync(file, "utf8"), tokens));
    continue;
  }
  if (
    !/\.tsx?$/.test(relative) ||
    /\.test\.tsx?$/.test(relative) ||
    relative.startsWith(`generated${path.sep}`)
  ) {
    continue;
  }
  const code = readFileSync(file, "utf8");
  findings.push(
    ...checkScript(
      relative,
      code,
      tokens,
      allowedScriptColors[relative]?.colors,
    ),
  );
  if (relative.startsWith(`components${path.sep}`)) {
    for (const [, imported] of code.matchAll(
      /from\s+["']([^"']+\.module\.css)["']/g,
    )) {
      const target = imported.startsWith("@/")
        ? path.join(source, imported.slice(2))
        : path.resolve(source, path.dirname(relative), imported);
      if (target.startsWith(path.join(source, "app") + path.sep)) {
        findings.push({
          file: relative,
          line: code.slice(0, code.indexOf(imported)).split("\n").length,
          message: `components must own their CSS, not import ${imported}.`,
        });
      }
    }
  }
}

if (findings.length) {
  for (const { file, line, message } of findings) {
    console.error(`src/${file}:${line}: ${message}`);
  }
  console.error(
    `\n${findings.length} design-system findings. Use the generated tokens in src/styles/generated-tokens.css, adding a token in packages/design-system/tokens when none fits.`,
  );
  process.exitCode = 1;
} else {
  console.log(
    "Web styles and scripts draw every visual value from the design tokens.",
  );
}
