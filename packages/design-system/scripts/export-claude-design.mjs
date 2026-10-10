import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdir, readdir, rm, writeFile } from "node:fs/promises";
import { basename, dirname, join, relative, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { buildBundle } from "./claude-design/bundle.mjs";
import { bundled, excluded, specOnlyGroups } from "./claude-design/catalog.mjs";
import {
  componentNames,
  makeDeclarations,
} from "./claude-design/declarations.mjs";
import {
  checkSpecAgainstComponent,
  componentReadme,
  loadSpecs,
  specOnlyReadme,
} from "./claude-design/docs.mjs";
import {
  buildPreview,
  buildSpecPreview,
  readSpecimens,
  specimenOrder,
} from "./claude-design/previews.mjs";
import { makeReadme } from "./claude-design/readme.mjs";
import { makeTokens } from "./claude-design/tokens.mjs";
import { validateProject } from "./claude-design/validate.mjs";
import { parseManifest } from "./lib/contrast.mjs";
import { validateIcons } from "./lib/icons.mjs";
import { readJson, resolveSystem } from "./lib/resolve.mjs";

// Exports the design system as a Claude Design System file tree.
//
// The repository is the single source of truth; the Claude Design copy is a display copy that this
// script regenerates from the tokens, icons, contrast pairs, component specs, and Web components.
// It writes <output>/project/: tokens.json, the README.md brand book, and components/ with one
// folder per component plus the bundle that renders them. Nothing it writes is committed.
//
//   node scripts/export-claude-design.mjs [output] [--specs <directory>]
//
// The output defaults to dist/claude-design in this package. A Cover card that someone else placed
// in project/components/Cover is kept.

export const packageRoot = resolve(
  dirname(fileURLToPath(import.meta.url)),
  "..",
);
export const repositoryRoot = resolve(packageRoot, "../..");
export const defaultOutput = resolve(packageRoot, "dist/claude-design");
const webRoot = resolve(repositoryRoot, "apps/web");
const tokenDirectory = resolve(packageRoot, "tokens");
const keptComponents = new Set(["Cover"]);

export async function exportClaudeDesign({
  output = defaultOutput,
  specsDirectory = resolve(packageRoot, "components"),
} = {}) {
  const system = await resolveSystem({
    resolverPath: resolve(tokenDirectory, "soft-ledger.resolver.json"),
    tokenDirectory,
    root: repositoryRoot,
  });
  const icons = validateIcons(
    await readJson(resolve(packageRoot, "icons.json"), repositoryRoot),
    system.platforms.web.light,
  );
  const contrast = parseManifest(
    await readJson(resolve(packageRoot, "contrast.json"), repositoryRoot),
  );
  const iconNames = icons.icons
    .filter((icon) => icon.platforms.includes("web"))
    .map((icon) => icon.name);

  const { tokens, stylesheet } = makeTokens({
    system,
    contrast,
    meta: sourceMeta(),
    title: `MemoTrail ${system.name}`,
  });
  const tokenNames = new Set(
    Object.values(tokens).flatMap((family) =>
      (family?.tokens ?? []).map((token) => token.name),
    ),
  );
  for (const group of tokens.type.groups) {
    for (const style of group.styles) tokenNames.add(style.name);
  }

  const specs = await loadSpecs(specsDirectory, repositoryRoot);
  const specsByName = new Map(specs.map((spec) => [spec.name, spec]));
  const bundle = await buildBundle({
    webRoot,
    components: bundled,
    stylesheet,
  });
  const declarations = makeDeclarations({
    webRoot,
    packageRoot,
    components: bundled,
    iconNames,
  });

  const files = new Map();
  for (const component of bundled) {
    const spec = specsByName.get(component.name);
    if (spec) checkSpecAgainstComponent(spec, component);
    const available = await readSpecimens(component.name, iconNames);
    const order = specimenOrder(component.name, available, spec);
    files.set(
      `components/${component.name}/preview.html`,
      await buildPreview({ component, order, iconNames }),
    );
    files.set(
      `components/${component.name}/README.md`,
      componentReadme({
        component,
        spec,
        declarations,
        specimens: order,
        tokenNames,
      }),
    );
  }

  const specOnly = specs.filter(
    (spec) => !bundled.some((component) => component.name === spec.name),
  );
  for (const spec of specOnly) {
    const reason = specOnlyReason(spec);
    const group = specOnlyGroups[spec.name];
    if (!group) {
      throw new Error(
        `${spec.label} describes ${spec.name}, which the bundle leaves out. Add its card group to specOnlyGroups in scripts/claude-design/catalog.mjs.`,
      );
    }
    files.set(
      `components/${spec.name}/preview.html`,
      buildSpecPreview({ spec, group, reason }),
    );
    files.set(
      `components/${spec.name}/README.md`,
      specOnlyReadme(spec, reason, tokenNames),
    );
  }

  files.set("tokens.json", `${JSON.stringify(tokens, null, 2)}\n`);
  files.set(
    "README.md",
    await makeReadme({
      system,
      contrast,
      icons,
      tokens,
      components: bundled,
      specOnly,
    }),
  );
  files.set("components/bundle.js", bundle.script);
  files.set("components/bundle.css", bundle.css);
  files.set("components/index.d.ts", declarations.text);

  const project = join(output, "project");
  await clean(project);
  for (const [path, contents] of files) {
    const target = join(project, path);
    await mkdir(dirname(target), { recursive: true });
    await writeFile(target, contents, "utf8");
  }

  const { problems } = await validateProject(project);
  if (problems.length > 0) {
    throw new Error(
      `The export does not fit the Claude Design format:\n${problems.join("\n")}`,
    );
  }

  return {
    project,
    files: [...files.keys()],
    tokens,
    bundled: bundle.names,
    components: bundled.map((component) => component.name),
    specOnly: specOnly.map((spec) => spec.name),
    excluded,
  };
}

// A spec with no bundled component explains why on its card and README.
function specOnlyReason(spec) {
  const owner = bundled.find((component) =>
    componentNames(component).includes(spec.name),
  );
  if (owner) {
    throw new Error(
      `${spec.label} describes ${spec.name}, which catalog.mjs bundles as a part of ${owner.name}. Describe it in the ${owner.name} spec instead.`,
    );
  }
  const web = spec.platforms?.web;
  if (!web || web.unavailable) {
    return `Web has no ${spec.name}, so this card describes the spec instead of rendering it.${web?.unavailable ? ` ${web.unavailable.trim()}` : ""}`;
  }
  const file = basename(web.path ?? "");
  const sharing = bundled.find((component) => component.source === file);
  if (excluded[file]) {
    return `The bundle leaves ${spec.name} out, so this card describes the spec instead of rendering it. ${excluded[file]}`;
  }
  throw new Error(
    sharing
      ? `${spec.label} points at ${file}, which catalog.mjs bundles as ${sharing.name}, not ${spec.name}.`
      : `${spec.label} points at ${web.path}, which catalog.mjs neither bundles nor excludes.`,
  );
}

function sourceMeta() {
  const git = (...args) =>
    execFileSync("git", args, { cwd: repositoryRoot, encoding: "utf8" }).trim();
  return {
    source: "github",
    repo: "ryangandev/memotrail",
    ref: `${git("rev-parse", "--abbrev-ref", "HEAD")}@${git("rev-parse", "--short", "HEAD")}`,
    package: relative(repositoryRoot, packageRoot),
    synced: git("log", "-1", "--format=%cs"),
  };
}

// Removes the previous export, except the cards in keptComponents.
async function clean(project) {
  if (!existsSync(project)) return;
  for (const entry of await readdir(project)) {
    if (entry !== "components")
      await rm(join(project, entry), { recursive: true, force: true });
  }
  const components = join(project, "components");
  if (!existsSync(components)) return;
  for (const entry of await readdir(components)) {
    if (!keptComponents.has(entry)) {
      await rm(join(components, entry), { recursive: true, force: true });
    }
  }
}

// pnpm runs package scripts from the package, so relative paths follow the caller's directory.
const invocationDirectory = process.env.INIT_CWD ?? process.cwd();

function parseArguments(argv) {
  const options = {};
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--specs") {
      options.specsDirectory = resolve(
        invocationDirectory,
        argv[(index += 1)] ?? "",
      );
    } else if (argument.startsWith("--")) {
      throw new Error(`Unknown option ${argument}.`);
    } else if (options.output) {
      throw new Error("Pass one output directory.");
    } else {
      options.output = resolve(invocationDirectory, argument);
    }
  }
  return options;
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const result = await exportClaudeDesign(
      parseArguments(process.argv.slice(2)),
    );
    const families = Object.entries(result.tokens)
      .filter(([, value]) => Array.isArray(value?.tokens))
      .map(([family, value]) => `${family} ${value.tokens.length}`);
    const styles = result.tokens.type.groups.reduce(
      (total, group) => total + group.styles.length,
      0,
    );
    console.log(
      [
        `Exported the Claude Design copy to ${result.project}: ${result.files.length} files.`,
        `Tokens: ${families.join(", ")}; ${styles} text styles.`,
        `Components: ${result.components.join(", ")}.`,
        `Bundle exports: ${result.bundled.join(", ")}.`,
        result.specOnly.length > 0
          ? `Spec only: ${result.specOnly.join(", ")}.`
          : "Every spec has a bundled component.",
        `Left out: ${Object.keys(result.excluded).length} component files; scripts/claude-design/catalog.mjs says why.`,
      ].join("\n"),
    );
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
