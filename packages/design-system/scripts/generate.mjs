import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { loadComponentSpecs } from "./lib/components.mjs";
import { checkContrast } from "./lib/contrast.mjs";
import { validateIcons } from "./lib/icons.mjs";
import { readJson, resolveSystem } from "./lib/resolve.mjs";
import { makeComponentSwift, makeSwift } from "./lib/swift.mjs";
import { makeCatalog, makeCss, makeTypeScript } from "./lib/web.mjs";

// Reads the DTCG 2025.10 resolver in tokens/, resolves it for each platform and theme,
// validates the icon manifest, WCAG contrast, and the component specs in components/, and
// writes the Web CSS variables, the Web gallery catalog, typed Web data with the component
// variants, the Swift tokens, and the Swift component variants.
//
//   node scripts/generate.mjs            write every output
//   node scripts/generate.mjs --check    fail when an output is missing or stale
//   node scripts/generate.mjs --contrast print every contrast pair and its ratio

const packageRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const repositoryRoot = resolve(packageRoot, "../..");
const tokenDirectory = resolve(packageRoot, "tokens");
const sourceLabel = relative(repositoryRoot, tokenDirectory);
const packageLabel = relative(repositoryRoot, packageRoot);
const output = (path) => resolve(repositoryRoot, path);
const checkOnly = process.argv.includes("--check");
const printContrast = process.argv.includes("--contrast");

async function main() {
  const system = await resolveSystem({
    resolverPath: resolve(tokenDirectory, "soft-ledger.resolver.json"),
    tokenDirectory,
    root: repositoryRoot,
  });
  const icons = validateIcons(
    await readJson(resolve(packageRoot, "icons.json"), repositoryRoot),
    system.platforms.web.light,
  );
  const contrast = checkContrast(
    await readJson(resolve(packageRoot, "contrast.json"), repositoryRoot),
    system,
  );

  if (printContrast) {
    for (const result of contrast.results) {
      console.log(
        [
          result.passes ? "pass" : "FAIL",
          result.platform.padEnd(3),
          result.theme.padEnd(5),
          `${result.ratio.toFixed(2)}:1`.padStart(8),
          `>= ${result.minimum}`,
          `{${result.text}} on ${result.on.map((path) => `{${path}}`).join(" over ")}`,
        ].join("  "),
      );
    }
  }
  if (contrast.error) throw new Error(contrast.error);
  if (printContrast) return;

  const components = await loadComponentSpecs({
    componentDirectory: resolve(packageRoot, "components"),
    schemaPath: resolve(packageRoot, "schema/component-spec.schema.json"),
    root: repositoryRoot,
    system,
  });

  const outputs = [
    [
      output("apps/web/src/styles/generated-tokens.css"),
      makeCss(system, sourceLabel, icons),
    ],
    [
      output("apps/web/src/generated/design-tokens.json"),
      makeCatalog(system, icons),
    ],
    [
      output("apps/web/src/generated/design-system.ts"),
      makeTypeScript(system, icons, packageLabel, components),
    ],
    [
      output("apps/ios/MemoTrail/DesignSystem/Generated/DesignTokens.swift"),
      makeSwift(system, icons, packageLabel),
    ],
    [
      output(
        "apps/ios/MemoTrail/DesignSystem/Generated/ComponentVariants.swift",
      ),
      makeComponentSwift(components, packageLabel),
    ],
  ];

  if (checkOnly) {
    const stale = [];

    for (const [path, expected] of outputs) {
      try {
        const actual = await readFile(path, "utf8");
        if (actual !== expected) stale.push(relative(repositoryRoot, path));
      } catch {
        stale.push(relative(repositoryRoot, path));
      }
    }

    if (stale.length > 0) {
      throw new Error(
        `Generated design tokens are missing or stale:\n${stale.join("\n")}\nRun pnpm design-system:generate.`,
      );
    }

    console.log(
      `Generated design tokens are current. Contrast: ${contrast.results.length} checks pass AA or have one of ${contrast.exceptions.length} named exceptions. Components: ${components.length} specs with ${components.reduce((count, spec) => count + spec.specimens.length, 0)} specimens are valid.`,
    );
  } else {
    for (const [path, contents] of outputs) {
      await mkdir(dirname(path), { recursive: true });
      await writeFile(path, contents, "utf8");
    }

    console.log(
      "Generated Web and Swift design tokens and component variants.",
    );
  }
}

try {
  await main();
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
