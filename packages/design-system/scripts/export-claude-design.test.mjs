import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import {
  mkdir,
  mkdtemp,
  readdir,
  readFile,
  rm,
  writeFile,
} from "node:fs/promises";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { after, before, describe, test } from "node:test";
import vm from "node:vm";
import {
  bundled,
  cardGroups,
  cardName,
  excluded,
  specName,
} from "./claude-design/catalog.mjs";
import { componentNames } from "./claude-design/declarations.mjs";
import {
  checkSpecAgainstComponent,
  loadSpecs,
  normalizeSpec,
} from "./claude-design/docs.mjs";
import { specimenOrder, specPreviewHeight } from "./claude-design/previews.mjs";
import { tokenNamePattern } from "./claude-design/tokens.mjs";
import {
  cardMarker,
  isColor,
  validateProject,
} from "./claude-design/validate.mjs";
import {
  exportClaudeDesign,
  packageRoot,
  repositoryRoot,
} from "./export-claude-design.mjs";

const require = createRequire(import.meta.url);
const fixtureSpecs = resolve(
  packageRoot,
  "scripts/claude-design/fixtures/specs",
);
const webComponents = resolve(repositoryRoot, "apps/web/src/components");

let output;
let project;
let result;
let tokens;

before(async () => {
  output = await mkdtemp(join(tmpdir(), "memotrail-claude-design-"));
  project = join(output, "project");
  // A Cover card placed by someone else survives an export; a stale folder does not.
  await mkdir(join(project, "components/Cover"), { recursive: true });
  await writeFile(
    join(project, "components/Cover/preview.html"),
    '<!-- @dsCard group="Foundations" height=400 -->\n<div id="root"></div>\n',
  );
  await mkdir(join(project, "components/Removed"), { recursive: true });
  await writeFile(join(project, "components/Removed/README.md"), "Stale.\n");
  result = await exportClaudeDesign({ output, specsDirectory: fixtureSpecs });
  tokens = JSON.parse(await readFile(join(project, "tokens.json"), "utf8"));
});

after(async () => {
  if (output) await rm(output, { recursive: true, force: true });
});

function families() {
  return Object.entries(tokens).filter(
    ([key, value]) =>
      !["name", "version", "meta", "type"].includes(key) &&
      value &&
      typeof value === "object",
  );
}

describe("tokens.json", () => {
  test("names its source", () => {
    assert.equal(tokens.version, 1);
    assert.equal(tokens.meta.source, "github");
    assert.equal(tokens.meta.repo, "ryangandev/memotrail");
    assert.equal(tokens.meta.package, "packages/design-system");
    assert.match(tokens.meta.ref, /^.+@[0-9a-f]{7,}$/);
    assert.match(tokens.meta.synced, /^\d{4}-\d{2}-\d{2}$/);
  });

  test("lists every family other than type as name, value, and usage", () => {
    const listed = families();
    for (const family of ["color", "spacing", "radius", "shadow"]) {
      assert.ok(tokens[family], `${family} is present`);
    }
    for (const [family, value] of listed) {
      assert.ok(Array.isArray(value.tokens), `${family}.tokens is a list`);
      assert.ok(value.tokens.length > 0, `${family} has tokens`);
      for (const token of value.tokens) {
        assert.deepEqual(
          Object.keys(token).sort(),
          ["name", "usage", "value"],
          token.name,
        );
        assert.ok(token.usage.trim().length > 10, `${token.name} has a usage`);
      }
    }
    const extras = listed.filter(
      ([family]) => !["color", "spacing", "radius", "shadow"].includes(family),
    );
    assert.ok(extras.length <= 12, "at most 12 extra families");
    for (const [family, value] of extras) {
      assert.ok(value.tokens.length <= 60, `${family} has at most 60 tokens`);
    }
  });

  test("keeps one component's geometry apart from the shared size scale", () => {
    const names = (family) => tokens[family].tokens.map(({ name }) => name);
    assert.ok(names("size").includes("mt-size-icon-16"));
    assert.ok(names("size").includes("mt-size-hit-target"));
    assert.ok(names("componentSize").includes("mt-size-checkbox-small"));
    assert.ok(!names("size").includes("mt-size-checkbox-small"));
  });

  test("names match the copy's pattern, the Web variables, and are unique", async () => {
    const names = families().flatMap(([, value]) =>
      value.tokens.map((token) => token.name),
    );
    for (const name of names) assert.match(name, tokenNamePattern);
    assert.equal(new Set(names).size, names.length);
    const css = await readFile(
      resolve(repositoryRoot, "apps/web/src/styles/generated-tokens.css"),
      "utf8",
    );
    for (const name of names)
      assert.ok(css.includes(`--${name}:`), `--${name} is a Web variable`);
  });

  test("colors use only hex, plain color functions, or aliases, in both themes", () => {
    assert.deepEqual(
      tokens.color.themes.map((theme) => theme.id),
      ["light", "dark"],
    );
    const names = new Set(tokens.color.tokens.map((token) => token.name));
    for (const token of tokens.color.tokens) {
      assert.deepEqual(
        Object.keys(token.value).sort(),
        ["dark", "light"],
        token.name,
      );
      for (const value of Object.values(token.value)) {
        assert.ok(isColor(value), `${token.name}: ${value}`);
        assert.doesNotMatch(value, /color-mix|var\(|^[a-z]+$/i);
        const alias = value.match(/^\{(.+)\}$/)?.[1];
        if (alias) assert.ok(names.has(alias), `${token.name} aliases a color`);
      }
    }
    const mixed = tokens.color.tokens.find(
      (token) => token.name === "mt-color-accent-tint",
    );
    assert.match(mixed.value.light, /^rgba\(/);
    assert.match(mixed.usage, /Mixes .*color-mix\(\)/);
  });

  test("no value uses var(), url(), or color-mix()", () => {
    const values = [
      ...families().flatMap(([, value]) =>
        value.tokens.map((token) => token.value),
      ),
      tokens.type.families,
      tokens.type.groups,
    ];
    assert.doesNotMatch(JSON.stringify(values), /var\(|url\(|color-mix\(/);
  });

  test("lengths use px, rem, em, %, or a number", () => {
    for (const family of ["spacing", "radius"]) {
      for (const token of tokens[family].tokens) {
        assert.match(
          String(token.value),
          /^-?\d+(\.\d+)?(px|rem|em|%)?$/,
          token.name,
        );
      }
    }
  });

  test("text colors list their grounds and exceptions from contrast.json", () => {
    const ink = tokens.color.tokens.find(
      (token) => token.name === "mt-color-ink-faint",
    );
    assert.match(ink.usage, /reads on mt-color-canvas/);
    assert.match(ink.usage, /Contrast exception "inkFaint metadata"/);
  });

  test("type groups come from the text roles and families from the font stacks", () => {
    assert.deepEqual(tokens.type.fonts, []);
    assert.deepEqual(Object.keys(tokens.type.families).sort(), [
      "mono",
      "sans",
      "serif",
    ]);
    const styles = tokens.type.groups.flatMap((group) => group.styles);
    const body = styles.find((style) => style.name === "mt-type-body");
    assert.equal(body.fontSize, "15px");
    assert.match(body.usage, /Dynamic Type/);
    for (const group of tokens.type.groups) {
      assert.ok(
        tokens.type.families[group.family],
        `${group.name} has a family`,
      );
    }
  });
});

describe("components", () => {
  test("every bundled component and spec has a README and a preview with a valid marker", async () => {
    const expected = [...bundled.map((component) => component.name), "Dialog"];
    for (const name of expected) {
      const folder = join(project, "components", name);
      const readme = await readFile(join(folder, "README.md"), "utf8");
      assert.ok(readme.trim().length > 100, `${name} README has content`);
      assert.doesNotMatch(readme, /^#\s/, `${name} README has no title`);
      const preview = await readFile(join(folder, "preview.html"), "utf8");
      const marker = preview.split("\n", 1)[0].match(cardMarker);
      assert.ok(marker, `${name} preview starts with a marker`);
      assert.ok(cardGroups.includes(marker[1]));
      assert.match(
        preview,
        /^<!--[^\n]*-->\n<div id="root"><\/div>\n<script>\n[\s\S]*<\/script>\n$/,
      );
      const script = preview.slice(
        preview.indexOf("<script>") + 8,
        preview.lastIndexOf("</script>"),
      );
      assert.doesNotMatch(script, /<\/script|<!--/i);
    }
  });

  test("a spec drives its README and the preview's specimen captions", async () => {
    const readme = await readFile(
      join(project, "components/Badge/README.md"),
      "utf8",
    );
    assert.ok(readme.startsWith("A single-line, noninteractive label"));
    for (const heading of [
      "Use",
      "Avoid",
      "Anatomy",
      "Props",
      "States",
      "Content",
      "Accessibility",
      "Platform differences",
      "Tokens",
      "Web props",
      "Specimens",
      "Source",
    ]) {
      assert.match(readme, new RegExp(`^## ${heading}$`, "m"), heading);
    }
    assert.match(
      readme,
      /`tone` \| `accent`, `neutral`, `warm`, `outline` \| `accent`/,
    );
    assert.match(readme, /Named `isUppercase` on iOS\./);
    assert.match(
      readme,
      /When tone is `accent` or `neutral`: `container` material `mt-material-chip-\*` on Web only/,
    );
    const preview = await readFile(
      join(project, "components/Badge/preview.html"),
      "utf8",
    );
    assert.match(preview, /Glass and inverse tones over a photo\./);
  });

  test("a spec without a bundled component gets a card that explains why", async () => {
    const readme = await readFile(
      join(project, "components/Dialog/README.md"),
      "utf8",
    );
    assert.match(readme, /The bundle leaves Dialog out/);
    assert.match(readme, /^- iOS: not available\./m);
    assert.match(readme, /^## Platform differences\n\nNone\.$/m);
    assert.deepEqual(result.specOnly, ["Dialog"]);
  });

  test("a component without a spec gets a README from its props", async () => {
    const readme = await readFile(
      join(project, "components/TextField/README.md"),
      "utf8",
    );
    assert.match(readme, /This component has no spec yet/);
    assert.match(readme, /\| `label` \| `string` \|  \| Required\. \|/);
    assert.match(readme, /native `<input>`/);
  });

  test("keeps a Cover card and removes stale folders", () => {
    assert.ok(existsSync(join(project, "components/Cover/preview.html")));
    assert.ok(!existsSync(join(project, "components/Removed")));
  });

  test("the bundle header lists exactly what window.MemoTrail exposes", async () => {
    const script = await readFile(
      join(project, "components/bundle.js"),
      "utf8",
    );
    const header = JSON.parse(
      script.split("\n", 1)[0].match(/^\/\* @ds-bundle: (\{.*\}) \*\/$/)[1],
    );
    assert.equal(header.format, 4);
    assert.equal(header.namespace, "MemoTrail");
    // The bundle only defines components when it runs, so Node's React 18 stands in for the UMD.
    const window = { React: require("react"), ReactDOM: require("react-dom") };
    vm.runInContext(script, vm.createContext({ window }));
    const listed = header.components.map((component) => component.name);
    assert.deepEqual(Object.keys(window.MemoTrail), listed);
    assert.deepEqual(listed, bundled.flatMap(componentNames));
  });

  test("bundle.js is one classic script with no imports, network, or markup breakers", async () => {
    const script = await readFile(
      join(project, "components/bundle.js"),
      "utf8",
    );
    assert.doesNotMatch(script, /<\/script/i);
    assert.doesNotMatch(script, /<!--/);
    assert.doesNotMatch(
      script,
      /^\s*import[\s{*]|\bimport\(|\bfetch\(|XMLHttpRequest|https?:\/\/(?!www\.w3\.org)/m,
    );
    assert.ok(Buffer.byteLength(script) <= 6 * 1024 * 1024);
  });

  test("bundle.css adds only the variables tokens.json cannot express", async () => {
    const css = await readFile(join(project, "components/bundle.css"), "utf8");
    const names = new Set(
      families().flatMap(([, value]) =>
        value.tokens.map((token) => token.name),
      ),
    );
    const declared = new Set(
      [...css.matchAll(/(?:^|[;{\s])--([\w-]+)\s*:/g)].map((match) => match[1]),
    );
    for (const name of declared)
      assert.ok(!names.has(name), `bundle.css redeclares --${name}`);
    const generated = await readFile(
      resolve(repositoryRoot, "apps/web/src/styles/generated-tokens.css"),
      "utf8",
    );
    for (const [, name] of generated.matchAll(/^\s*--([\w-]+):/gm)) {
      assert.ok(
        names.has(name) || declared.has(name),
        `--${name} reaches the copy`,
      );
    }
    assert.match(css, /^:root \{/);
    assert.match(css, /\[data-theme="dark"\] \{\n  color-scheme: dark;/);
    assert.doesNotMatch(css, /@font-face|@import/);
  });

  test("index.d.ts declares every bundled export on window.MemoTrail", async () => {
    const text = await readFile(join(project, "components/index.d.ts"), "utf8");
    assert.match(text, /declare namespace MemoTrail \{/);
    assert.match(text, /interface Window \{\n\s+MemoTrail: typeof MemoTrail;/);
    for (const name of bundled.flatMap(componentNames)) {
      assert.match(
        text,
        new RegExp(`export (function|const) ${name}\\b`),
        name,
      );
    }
  });

  test("index.d.ts writes out the generated unions the components use, in their order", async () => {
    const text = await readFile(join(project, "components/index.d.ts"), "utf8");
    const generated = await readFile(
      resolve(repositoryRoot, "apps/web/src/generated/design-system.ts"),
      "utf8",
    );
    const lists = new Map(
      [
        ...generated.matchAll(
          /^export const (\w+) = \[([^\]]*)\] as const;$/gm,
        ),
      ].map((match) => [match[1], [...match[2].matchAll(/"([^"]*)"/g)]]),
    );
    const aliases = [
      ...generated.matchAll(
        /^export type (\w+) = \(typeof (\w+)\)\[number\];$/gm,
      ),
    ];
    const copied = aliases.filter(([, alias]) =>
      text.includes(`export type ${alias} =`),
    );
    for (const name of ["IconName", "BadgeTone", "ButtonVariant"]) {
      assert.ok(
        copied.some(([, alias]) => alias === name),
        `copies ${name}`,
      );
    }
    for (const [, alias, list] of copied) {
      const declared = text.match(
        new RegExp(`export type ${alias} =([^;]*);`),
      )[1];
      assert.deepEqual(
        [...declared.matchAll(/"([^"]*)"/g)].map((match) => match[1]),
        lists.get(list).map((match) => match[1]),
        alias,
      );
    }
    assert.doesNotMatch(text, /typeof \w+\)\[number\]/);
    assert.doesNotMatch(text, /from "@\//);
  });

  test("the catalog lists every Web component file exactly once", async () => {
    const files = (await readdir(webComponents)).filter(
      (file) => /\.tsx?$/.test(file) && !/\.test\.tsx?$/.test(file),
    );
    const sources = new Set(bundled.map((component) => component.source));
    for (const file of files) {
      assert.ok(
        sources.has(file) !== Boolean(excluded[file]),
        `${file} is bundled or excluded, not both`,
      );
    }
    for (const file of [...sources, ...Object.keys(excluded)]) {
      assert.ok(files.includes(file), `${file} exists`);
    }
  });
});

describe("README.md", () => {
  test("is the brand book, with every placeholder filled", async () => {
    const readme = await readFile(join(project, "README.md"), "utf8");
    assert.doesNotMatch(readme, /^#\s/m, "no title");
    assert.doesNotMatch(readme, /\{\{|\}\}/);
    for (const heading of [
      "Content fundamentals",
      "Visual foundations",
      "Iconography",
      "Web and iOS",
      "Components",
    ]) {
      assert.match(readme, new RegExp(`^## ${heading}$`, "m"));
    }
    assert.match(
      readme,
      /\| `mt-color-accent` \| `#[0-9A-F]{6}` \| `#[0-9A-F]{6}` \|/,
    );
    assert.match(readme, /\| `calendar` \| `calendar` \| yes \|/);
    assert.match(readme, /\[Dialog\]\(components\/Dialog\/README\.md\)/);
  });

  test("quotes copy that exists in the Web app", async () => {
    const readme = await readFile(join(project, "README.md"), "utf8");
    const quotes = [...readme.matchAll(/^- "(.+)"$/gm)].map(
      (match) => match[1],
    );
    assert.ok(quotes.length >= 10);
    const sources = await webSources(resolve(repositoryRoot, "apps/web/src"));
    for (const quote of quotes) assert.ok(sources.includes(quote), quote);
  });
});

test("exports with the repository's own component specs", async () => {
  const own = await mkdtemp(join(tmpdir(), "memotrail-claude-design-specs-"));
  try {
    const exported = await exportClaudeDesign({ output: own });
    const specs = await loadSpecs(
      resolve(packageRoot, "components"),
      repositoryRoot,
    );
    assert.ok(specs.length > 0);
    for (const spec of specs) {
      const readme = await readFile(
        join(exported.project, `components/${cardName(spec.name)}/README.md`),
        "utf8",
      );
      for (const specimen of spec.specimens) {
        assert.match(readme, new RegExp(`^- \`${specimen.id}\`: `, "m"));
      }
      // The spec's props, then the Web props of the component and each part that takes the prop,
      // list every value, and Web defaults show the literal read from the generated constants.
      // A spec-only card has no bundled component, so it lists only the spec's rows.
      const specOnly = exported.specOnly.includes(spec.name);
      for (const [name, prop] of Object.entries(spec.props)) {
        if (!prop.values || prop.platforms?.includes("web") === false) continue;
        const rows = readme
          .split("\n")
          .filter((line) => line.startsWith(`| \`${name}\` |`));
        const [specRow, ...webRows] = rows;
        assert.ok(specRow, `${spec.name} ${name} has a spec row`);
        assert.equal(
          webRows.length > 0,
          !specOnly,
          `${spec.name} ${name} has Web rows only when bundled`,
        );
        for (const value of prop.values) {
          assert.ok(specRow.includes(`\`${value}\``), `${name} ${value}`);
          for (const row of webRows) {
            assert.ok(row.includes(`"${value}"`), `Web ${name} ${value}`);
          }
        }
        for (const row of webRows) {
          assert.ok(row.includes(`| \`"${prop.default}"\` |`), row);
        }
      }
    }
  } finally {
    await rm(own, { recursive: true, force: true });
  }
});

test("a bundled component can follow a spec with another name", async () => {
  // DatePickerField is the Web side of the DateField spec, so its card shows that spec.
  const datePicker = bundled.find(({ name }) => name === "DatePickerField");
  assert.equal(specName(datePicker), "DateField");
  assert.equal(cardName("DateField"), "DatePickerField");
  assert.equal(cardName("Badge"), "Badge");
  assert.equal(cardName("Toast"), "Toast");
  const own = await mkdtemp(
    join(tmpdir(), "memotrail-claude-design-spec-name-"),
  );
  try {
    const exported = await exportClaudeDesign({ output: own });
    assert.ok(!exported.specOnly.includes("DateField"));
    const readme = await readFile(
      join(exported.project, "components/DatePickerField/README.md"),
      "utf8",
    );
    assert.match(readme, /^- `date-field-precision`: /m);
  } finally {
    await rm(own, { recursive: true, force: true });
  }
});

test("no exported text uses the em dash", async () => {
  for (const file of result.files) {
    if (file.endsWith("bundle.js")) continue;
    const text = await readFile(join(project, file), "utf8");
    assert.ok(!text.includes("—"), file);
  }
});

test("the exported project passes the format check", async () => {
  const { problems } = await validateProject(project);
  assert.deepEqual(problems, []);
});

describe("spec checks", () => {
  const spec = (overrides) =>
    normalizeSpec(
      {
        name: "Badge",
        purpose: "A label.",
        platforms: {
          web: {
            path: "apps/web/src/components/badge.tsx",
            symbols: ["Badge"],
          },
        },
        specimens: [{ id: "badge-tones", description: "Tones." }],
        ...overrides,
      },
      "badge.yaml",
    );
  const badge = bundled.find((component) => component.name === "Badge");

  test("stops when the spec and the specimen file list different specimens", () => {
    assert.throws(
      () =>
        specimenOrder("Badge", [{ id: "badge-sizes", title: "Sizes" }], spec()),
      /list different specimens\. Render these in specimens\/Badge\.jsx: badge-tones\. List these in the spec, or remove them: badge-sizes\./,
    );
  });

  test("sizes a spec-only card to the lines its text wraps to", () => {
    const card = (purpose, reason, ...descriptions) =>
      specPreviewHeight({
        purpose,
        reason,
        specimens: descriptions.map((description) => ({ description })),
      });
    const short = card("Short.", "Short.", "One.");
    assert.equal(short, 112 + 22 + 2 * 18);
    // A purpose that wraps adds a body line, and a reason or specimen that wraps adds a caption line.
    assert.equal(card("x".repeat(79), "Short.", "One."), short + 22);
    assert.equal(card("Short.", "x".repeat(91), "One."), short + 18);
    assert.equal(card("Short.", "Short.", "x".repeat(87)), short + 18);
    assert.equal(card("Short.", "Short.", "One.", "Two."), short + 18);
  });

  test("follows the spec's specimen order and descriptions", () => {
    assert.deepEqual(
      specimenOrder("Badge", [{ id: "badge-tones", title: "Ignored" }], spec()),
      [{ id: "badge-tones", caption: "Tones." }],
    );
  });

  test("stops when the spec names exports the bundle lacks or another file", () => {
    assert.throws(
      () =>
        checkSpecAgainstComponent(
          spec({
            platforms: {
              web: {
                path: "apps/web/src/components/badge.tsx",
                symbols: ["Badge", "BadgeGroup"],
              },
            },
          }),
          badge,
        ),
      /lists BadgeGroup/,
    );
    assert.throws(
      () =>
        checkSpecAgainstComponent(
          spec({
            platforms: {
              web: {
                path: "apps/web/src/components/chip.tsx",
                symbols: ["Badge"],
              },
            },
          }),
          badge,
        ),
      /points Web at apps\/web\/src\/components\/chip\.tsx/,
    );
  });

  test("rejects specimen ids that are not kebab-case", () => {
    assert.throws(
      () => spec({ specimens: [{ id: "Tones", description: "Tones." }] }),
      /kebab-case id/,
    );
  });
});

async function webSources(directory) {
  const texts = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) texts.push(await webSources(path));
    else if (/\.tsx?$/.test(entry.name))
      texts.push(await readFile(path, "utf8"));
  }
  return texts.join("\n");
}
