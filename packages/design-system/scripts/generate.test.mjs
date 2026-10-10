import assert from "node:assert/strict";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { after, before, describe, test } from "node:test";
import { fileURLToPath } from "node:url";
import { stringify } from "yaml";
import { loadComponentSpecs, propertyTypes } from "./lib/components.mjs";
import { checkContrast, contrastRatio } from "./lib/contrast.mjs";
import { validateIcons } from "./lib/icons.mjs";
import { readJson, resolveSystem } from "./lib/resolve.mjs";
import { makeComponentSwift, makeSwift } from "./lib/swift.mjs";
import { makeCatalog, makeCss, makeTypeScript } from "./lib/web.mjs";

const packageRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const repositoryRoot = resolve(packageRoot, "../..");
const tokenDirectory = resolve(packageRoot, "tokens");
const componentDirectory = resolve(packageRoot, "components");
const schemaPath = resolve(packageRoot, "schema/component-spec.schema.json");

const px = (value) => ({ value, unit: "px" });
const srgb = (hex, alpha) => {
  const value = Number.parseInt(hex.slice(1), 16);
  const components = [value >> 16, (value >> 8) & 255, value & 255].map(
    (channel) => Math.round((channel / 255) * 10_000) / 10_000,
  );
  return {
    colorSpace: "srgb",
    components,
    hex,
    ...(alpha === undefined ? {} : { alpha }),
  };
};

const baseFoundation = {
  palette: {
    $type: "color",
    white: { $value: srgb("#FFFFFF") },
    ink: { $value: srgb("#26251F") },
  },
};

/** Resolves an inline token system with one foundation document and one document per theme. */
async function resolveInline({ foundation = {}, light = {}, dark = light }) {
  const directory = await mkdtemp(join(tmpdir(), "memotrail-tokens-"));
  const resolverPath = join(directory, "test.resolver.json");
  await writeFile(
    resolverPath,
    JSON.stringify({
      version: "2025.10",
      name: "Test",
      sets: { foundation: { sources: [{ ...baseFoundation, ...foundation }] } },
      modifiers: {
        theme: { contexts: { light: [light], dark: [dark] }, default: "light" },
      },
      resolutionOrder: [
        { $ref: "#/sets/foundation" },
        { $ref: "#/modifiers/theme" },
      ],
    }),
  );
  try {
    return await resolveSystem({
      resolverPath,
      tokenDirectory: directory,
      root: directory,
    });
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}

const bodyRole = {
  type: {
    $type: "typography",
    body: {
      $value: {
        fontFamily: "system-ui",
        fontSize: px(15),
        fontWeight: 400,
        letterSpacing: px(0),
        lineHeight: 1.5,
      },
      $extensions: { "com.memotrail": { ios: { textStyle: "subheadline" } } },
    },
  },
};

const colorTheme = (ink, surface) => ({
  color: {
    $type: "color",
    ink: { $value: srgb(ink) },
    surface: { $value: srgb(surface) },
  },
});

async function realSystem() {
  const system = await resolveSystem({
    resolverPath: resolve(tokenDirectory, "soft-ledger.resolver.json"),
    tokenDirectory,
    root: packageRoot,
  });
  const icons = validateIcons(
    await readJson(resolve(packageRoot, "icons.json"), packageRoot),
    system.platforms.web.light,
  );
  return { system, icons };
}

describe("the Soft Ledger tokens", async () => {
  const { system, icons } = await realSystem();
  const css = makeCss(system, "tokens");
  const swift = makeSwift(system, icons, "package");
  const catalog = JSON.parse(makeCatalog(system, icons));
  const typescript = makeTypeScript(system, icons, "package");

  test("keep Web-only tokens out of Swift and iOS-only tokens out of Web", () => {
    assert.match(css, /--mt-layout-layer-dialog: 70;/);
    assert.doesNotMatch(swift, /mapOverlay|nestedPopover|breakpoint/);
    assert.match(swift, /static let wordmarkLarge = MTTextRole\(/);
    assert.doesNotMatch(css, /wordmark-large/);
    assert.equal(catalog.type.wordmarkLarge, undefined);
  });

  test("emit a fluid Web role and its iOS override", () => {
    assert.match(css, /--mt-type-hero-font-size: clamp\(46px, 5\.5vw, 70px\);/);
    assert.match(css, /--mt-type-hero-letter-spacing: -0\.045em;/);
    assert.match(swift, /name: "hero", size: 50,/);
  });

  test("put theme-invariant tokens in :root and themed ones in each theme block", () => {
    const [root] = css.split(/\n\[data-theme|@media/);
    assert.match(
      root,
      /--mt-motion-easing-emphasized: cubic-bezier\(0\.22, 1, 0\.36, 1\);/,
    );
    assert.doesNotMatch(root, /--mt-color-canvas:/);
    assert.equal(css.match(/--mt-color-canvas:/g).length >= 2, true);
  });

  test("write mixed colors as the color-mix() they replace", () => {
    assert.match(
      css,
      /--mt-color-skeleton-highlight: color-mix\(in srgb, var\(--mt-color-surface-raised\) 72%, transparent\);/,
    );
    assert.match(
      css,
      /--mt-color-chip-surface: color-mix\(in srgb, var\(--mt-color-surface\) 72%, var\(--mt-color-surface-raised\)\);/,
    );
    assert.match(
      css,
      /--mt-color-media-control: color-mix\(in srgb, #000000 64%, transparent\);/,
    );
    // Without a mix, a translucent color stays the rgb() its source wrote.
    assert.match(css, /--mt-color-menu-scrim: rgb\(0 0 0 \/ 0\.48\);/);
    // The catalog and Swift keep the resolved value.
    assert.equal(
      catalog.color.light.skeletonHighlight,
      "rgb(255 255 255 / 0.72)",
    );
  });

  test("apply platform overrides only on their platform", () => {
    assert.equal(
      catalog.material.light.glassPanel.tint,
      "rgb(255 255 255 / 0.76)",
    );
    assert.match(
      swift,
      /lightOpacity: 0\.94, darkOpacity: 0\.94\),\n {4}border:/,
    );
  });

  test("generate the Web icon vocabulary without iOS-only names", () => {
    assert.match(typescript, /"sidebarOpen",/);
    assert.doesNotMatch(typescript, /"collection"/);
    assert.match(swift, /case collection = "square\.stack"/);
    assert.doesNotMatch(swift, /sidebarOpen/);
    assert.match(
      swift,
      /static let iosOnly: Set<MTIcon> = \[\n {4}\.collection,/,
    );
  });

  test("pass AA contrast or name every exception", async () => {
    const result = checkContrast(
      await readJson(resolve(packageRoot, "contrast.json"), packageRoot),
      system,
    );
    assert.equal(result.error, null);
    assert.ok(result.results.length > 0);
  });
});

describe("validation", () => {
  test("rejects an invalid hex color", async () => {
    await assert.rejects(
      resolveInline({
        light: {
          color: {
            $type: "color",
            ink: { $value: { ...srgb("#26251F"), hex: "#26251G" } },
          },
        },
      }),
      /\{color\.ink\}/,
    );
  });

  test("rejects a hex that disagrees with its components", async () => {
    await assert.rejects(
      resolveInline({
        light: {
          color: {
            $type: "color",
            ink: { $value: { ...srgb("#26251F"), hex: "#000000" } },
          },
        },
      }),
      /\{color\.ink\}/,
    );
  });

  test("rejects a cubic Bezier whose x values leave 0 to 1", async () => {
    await assert.rejects(
      resolveInline({
        foundation: {
          motion: {
            easing: { $type: "cubicBezier", bad: { $value: [1.2, 0, 0.5, 1] } },
          },
        },
        light: colorTheme("#26251F", "#FFFFFF"),
      }),
      /\{motion\.easing\.bad\}/,
    );
  });

  test("rejects an alias to a missing token", async () => {
    await assert.rejects(
      resolveInline({
        light: {
          color: { $type: "color", ink: { $value: "{palette.missing}" } },
        },
      }),
      /palette\.missing/,
    );
  });

  test("asks for inset shadows to be marked Web-only", async () => {
    await assert.rejects(
      resolveInline({
        foundation: {
          shadow: {
            $type: "shadow",
            inner: {
              $value: [
                {
                  color: srgb("#000000", 0.2),
                  offsetX: px(0),
                  offsetY: px(1),
                  blur: px(0),
                  spread: px(0),
                  inset: true,
                },
              ],
            },
          },
        },
        light: colorTheme("#26251F", "#FFFFFF"),
      }),
      /Web-only/,
    );
  });

  test("verifies a mixed color against the colors it claims to mix", async () => {
    const mixed = (hex) => ({
      color: {
        $type: "color",
        ink: { $value: srgb("#26251F") },
        surface: { $value: srgb("#FFFFFF") },
        wash: {
          $value: srgb(hex),
          $extensions: {
            "com.memotrail": {
              mix: { colors: ["{color.ink}", "{color.surface}"], weight: 0.5 },
            },
          },
        },
      },
    });
    await resolveInline({ light: mixed("#93928F") });
    await assert.rejects(resolveInline({ light: mixed("#000000") }), /#93928F/);
  });

  test("requires both themes to define the same tokens", async () => {
    await assert.rejects(
      resolveInline({
        light: colorTheme("#26251F", "#FFFFFF"),
        dark: { color: { $type: "color", ink: { $value: srgb("#FFFFFF") } } },
      }),
      /same tokens/,
    );
  });

  test("requires an iOS text style for a text role on iOS", async () => {
    await assert.rejects(
      resolveInline({
        foundation: {
          type: {
            $type: "typography",
            body: {
              $value: {
                fontFamily: "system-ui",
                fontSize: px(15),
                fontWeight: 400,
                letterSpacing: px(0),
                lineHeight: 1.5,
              },
            },
          },
        },
        light: colorTheme("#26251F", "#FFFFFF"),
      }),
      /textStyle/,
    );
  });
});

describe("contrast", () => {
  test("measures the WCAG ratio", () => {
    assert.equal(contrastRatio([0, 0, 0], [255, 255, 255]).toFixed(2), "21.00");
    assert.equal(contrastRatio([255, 255, 255], [255, 255, 255]), 1);
  });

  test("fails a low-contrast pair unless it is a named exception, and flags stale exceptions", async () => {
    const system = await resolveInline({
      foundation: bodyRole,
      light: colorTheme("#9A9589", "#FFFFFF"),
    });
    const checks = [
      { text: "{color.ink}", on: ["{color.surface}"], role: "{type.body}" },
    ];
    const failing = checkContrast({ checks }, system);
    assert.match(failing.error, /color\.ink/);

    const excused = checkContrast(
      {
        checks,
        exceptions: [
          {
            name: "Faint ink",
            reason: "A test fixture kept on purpose.",
            text: "{color.ink}",
            on: "{color.surface}",
            themes: ["light", "dark"],
          },
        ],
      },
      system,
    );
    assert.equal(excused.error, null);

    const passing = await resolveInline({
      foundation: bodyRole,
      light: colorTheme("#26251F", "#FFFFFF"),
    });
    const stale = checkContrast(
      {
        checks,
        exceptions: [
          {
            name: "Faint ink",
            reason: "A test fixture kept on purpose.",
            text: "{color.ink}",
            on: "{color.surface}",
            themes: ["light", "dark"],
          },
        ],
      },
      passing,
    );
    assert.match(stale.error, /Faint ink/);
  });
});

describe("icons", () => {
  const webTokens = new Map([
    ["size.stroke.icon", { type: "dimension", value: 1.7 }],
  ]);

  test("require alphabetical names", () => {
    assert.throws(
      () =>
        validateIcons(
          {
            svg: { viewBox: "0 0 24 24", strokeWidth: "{size.stroke.icon}" },
            icons: {
              plus: {
                description: "Add.",
                sfSymbol: "plus",
                svg: [["path", { d: "M1 1" }]],
              },
              check: {
                description: "Done.",
                sfSymbol: "checkmark",
                svg: [["path", { d: "M1 1" }]],
              },
            },
          },
          webTokens,
        ),
      /alphabetical/,
    );
  });

  test("reject unsupported SVG elements", () => {
    assert.throws(
      () =>
        validateIcons(
          {
            svg: { viewBox: "0 0 24 24", strokeWidth: "{size.stroke.icon}" },
            icons: {
              plus: {
                description: "Add.",
                sfSymbol: "plus",
                svg: [["script", {}]],
              },
            },
          },
          webTokens,
        ),
      /script/,
    );
  });
});

describe("the component specs", async () => {
  const { system, icons } = await realSystem();
  const load = () =>
    loadComponentSpecs({
      componentDirectory,
      schemaPath,
      root: repositoryRoot,
      system,
    });
  const components = await load();
  const typescript = makeTypeScript(system, icons, "package", components);
  const swift = makeComponentSwift(components, "package");

  test("validate, sorted by file name", () => {
    assert.deepEqual(
      components.map(({ file }) => file),
      ["badge.yaml", "button.yaml"],
    );
  });

  test("emit each enum prop as a TypeScript value list and union", () => {
    assert.match(
      typescript,
      /export const badgeTones = \[\n {2}"accent",[\s\S]*"glassNeutral",\n\] as const;/,
    );
    assert.match(
      typescript,
      /export type BadgeTone = \(typeof badgeTones\)\[number\];/,
    );
    assert.match(
      typescript,
      /export const buttonSizes = \["small", "medium", "large"\] as const;/,
    );
  });

  test("leave props of other platforms out of each platform's defaults", () => {
    assert.match(
      typescript,
      /export const buttonDefaults = \{\n {2}variant: "primary",\n {2}size: "medium",\n {2}loading: false,\n\} as const;/,
    );
    assert.match(
      swift,
      /static let isLoading = false\n {2}static let fillsWidth = false/,
    );
  });

  test("emit each enum prop as a Swift enum with the spec's values", () => {
    assert.match(
      swift,
      /enum MTBadgeTone: String, CaseIterable, Sendable \{\n {2}case accent\n[\s\S]*?case glassNeutral\n\}/,
    );
    assert.match(swift, /static let tone = MTBadgeTone\.accent/);
  });

  test("list every specimen on both platforms in spec order", () => {
    const ids = components.flatMap(({ specimens }) =>
      specimens.map(({ id }) => id),
    );
    assert.ok(ids.length > 0);
    const webIds = [...typescript.matchAll(/^ {4}id: "([a-z-]+)",$/gm)].map(
      ([, id]) => id,
    );
    const swiftIds = [...swift.matchAll(/^ {2}case \w+ = "([a-z-]+)"$/gm)].map(
      ([, id]) => id,
    );
    assert.deepEqual(webIds, ids);
    assert.deepEqual(swiftIds, ids);
  });

  test("keep Swift summaries whole within swift-format's 100 columns", () => {
    const summaries = [
      "Short.",
      `A ${"medium ".repeat(9)}summary.`,
      `A "quoted" C:\\path and """ ${"long ".repeat(30)}summary.`,
    ];
    const [spec] = components;
    const generated = makeComponentSwift(
      [
        {
          ...spec,
          specimens: summaries.map((description, index) => ({
            ...spec.specimens[0],
            id: `${spec.specimens[0].id}-${index}`,
            description,
          })),
        },
      ],
      "package",
    );
    for (const line of generated.split("\n")) {
      assert.ok(line.length <= 100, line);
    }
    const body = generated
      .split("var summary: String {")[1]
      .split("\n    }")[0];
    const decoded = body
      .split(/^ {4}case [^:]+:/m)
      .slice(1)
      .map((value) => {
        const text = value.trim();
        if (!text.startsWith('"""')) {
          return text.slice(1, -1).replace(/\\(.)/g, "$1");
        }
        return text
          .slice(3, -3)
          .trim()
          .split("\n")
          .map((line) => line.trim())
          .join("\n")
          .replaceAll("\\\n", "")
          .replace(/\\(.)/g, "$1");
      });
    assert.deepEqual(decoded, summaries);
  });

  test("expand covers: all to every value", () => {
    const tones = components
      .find(({ name }) => name === "Badge")
      .specimens.find(({ id }) => id === "badge-tones").covers.tone;
    assert.deepEqual(
      tones,
      components
        .find(({ name }) => name === "Badge")
        .props.find(({ name }) => name === "tone").values,
    );
  });

  test("generate the same output every time", async () => {
    const again = await load();
    assert.equal(makeTypeScript(system, icons, "package", again), typescript);
    assert.equal(makeComponentSwift(again, "package"), swift);
  });

  test("give the schema exactly the part properties the checker knows", async () => {
    const schema = JSON.parse(await readFile(schemaPath, "utf8"));
    assert.deepEqual(
      Object.keys(schema.$defs.partTokens.properties).sort(),
      Object.keys(propertyTypes).sort(),
    );
  });
});

describe("component spec validation", async () => {
  const { system } = await realSystem();
  let root;

  before(async () => {
    root = await mkdtemp(join(tmpdir(), "memotrail-components-"));
    await mkdir(join(root, "apps/web"), { recursive: true });
    await mkdir(join(root, "apps/ios"), { recursive: true });
    await writeFile(
      join(root, "apps/web/chip.tsx"),
      "// Chip renders inside a ChipList.\nexport function Chip() {}\n",
    );
    await writeFile(join(root, "apps/ios/Chip.swift"), "struct MTChip {}\n");
  });
  after(() => rm(root, { recursive: true, force: true }));

  const chip = () => ({
    name: "Chip",
    platforms: {
      web: { path: "apps/web/chip.tsx", symbols: ["Chip"] },
      ios: { path: "apps/ios/Chip.swift", symbols: ["MTChip"] },
    },
    purpose: "A test component.",
    use: ["Tests."],
    avoid: ["Everything else."],
    anatomy: { container: "The chip.", label: "Its text." },
    props: {
      tone: {
        description: "The chip's color.",
        values: ["accent", "neutral"],
        default: "accent",
      },
      selected: {
        description: "Marks the chip as chosen.",
        type: "boolean",
        default: false,
      },
    },
    states: ["default", "pressed"],
    tokens: [
      { container: { radius: "{radius.pill}" } },
      { when: { tone: "accent" }, label: { color: "{color.accent}" } },
    ],
    content: {
      lines: 1,
      overflow: "truncateTail",
      casing: "sentence",
      length: "One word.",
    },
    accessibility: {
      role: "A button.",
      label: "Its text.",
      focus: "Takes focus.",
      minimumHitTarget: "{size.hitTarget}",
      dynamicType: "Scales.",
    },
    platformDifferences: [],
    specimens: [
      {
        id: "chip-tones",
        description: "Every tone.",
        covers: { tone: "all" },
      },
    ],
  });

  /** Writes the specs, given as file name to spec, into a fresh directory and loads them. */
  async function loadSpecs(specs) {
    const directory = await mkdtemp(join(root, "components-"));
    for (const [file, spec] of Object.entries(specs)) {
      await writeFile(
        join(directory, file),
        typeof spec === "string" ? spec : stringify(spec),
      );
    }
    return loadComponentSpecs({
      componentDirectory: directory,
      schemaPath,
      root,
      system,
    });
  }

  /** Loads the chip spec after `change` edits it. */
  function loadChip(change) {
    const spec = chip();
    change(spec);
    return loadSpecs({ "chip.yaml": spec });
  }

  test("accepts a valid spec", async () => {
    const [spec] = await loadChip(() => {});
    assert.deepEqual(spec.specimens[0].covers, { tone: ["accent", "neutral"] });
    assert.deepEqual(spec.props[1], {
      name: "selected",
      description: "Marks the chip as chosen.",
      kind: "boolean",
      values: null,
      default: false,
      platforms: ["web", "ios"],
      names: { web: "selected", ios: "selected" },
    });
  });

  const failures = [
    [
      "a field the schema does not know",
      (spec) => (spec.colour = "red"),
      /does not match the component spec schema[\s\S]*colour/,
    ],
    [
      "text that YAML cut off at a #",
      (spec) => (spec.purpose = "Tags with a leading"),
      /\/purpose must match pattern/,
    ],
    [
      "a missing platform file",
      (spec) => (spec.platforms.web.path = "apps/web/missing.tsx"),
      /apps\/web\/missing\.tsx does not exist/,
    ],
    [
      "a symbol the file only mentions",
      (spec) => (spec.platforms.web.symbols = ["Chip", "ChipList"]),
      /does not declare ChipList/,
    ],
    [
      "an unknown token",
      (spec) => (spec.tokens[0].container.radius = "{radius.huge}"),
      /references \{radius\.huge\}, which web lacks/,
    ],
    [
      "a token of the wrong type",
      (spec) => (spec.tokens[0].container.radius = "{color.accent}"),
      /needs a dimension token, but \{color\.accent\} is a color/,
    ],
    [
      "a private palette token",
      (spec) => (spec.tokens[1].label.color = "{palette.white}"),
      /private \{palette\.white\}/,
    ],
    [
      "a group where a token belongs",
      (spec) => (spec.tokens[0].container.radius = "{size.control}"),
      /references the group \{size\.control\}; name one of its tokens/,
    ],
    [
      "a material that is not a group",
      (spec) => (spec.tokens[0].container.material = "{color.accent}"),
      /must name a material group/,
    ],
    [
      "a default outside the values",
      (spec) => (spec.props.tone.default = "warm"),
      /props\.tone\.default warm is not one of its values/,
    ],
    [
      "a rule on an unknown prop",
      (spec) => (spec.tokens[1].when = { size: "small" }),
      /when\.size is not a prop/,
    ],
    [
      "a rule on an unknown value",
      (spec) => (spec.tokens[1].when = { tone: "warm" }),
      /when\.tone warm is not one of its values/,
    ],
    [
      "a rule on an unlisted state",
      (spec) => (spec.tokens[1].when = { state: "hover" }),
      /when\.state hover is not in states/,
    ],
    [
      "a rule on a part outside the anatomy",
      (spec) => (spec.tokens[0].icon = { color: "{color.accent}" }),
      /tokens\[0\]\.icon is not in anatomy/,
    ],
    [
      "a property set twice under the same conditions",
      (spec) => spec.tokens.push({ container: { radius: "{radius.small}" } }),
      /repeats tokens\[0\]\.container\.radius/,
    ],
    [
      "a platform value on a prop limited to the other platform",
      (spec) => {
        spec.props.selected.platforms = ["ios"];
        spec.tokens.push({
          when: { selected: true },
          label: { color: { web: "{color.ink}" } },
        });
      },
      /applies to a platform the rule never reaches/,
    ],
    [
      "a specimen id without the component's prefix",
      (spec) => (spec.specimens[0].id = "badge-tones"),
      /must start with chip-/,
    ],
    [
      "a specimen that covers a boolean prop",
      (spec) => (spec.specimens[0].covers = { selected: "all" }),
      /covers\.selected is not an enum prop/,
    ],
    [
      "a specimen that covers an unknown value",
      (spec) => (spec.specimens[0].covers = { tone: ["warm"] }),
      /covers\.tone warm is not one of its values/,
    ],
    [
      "a hit target that is not a dimension",
      (spec) => (spec.accessibility.minimumHitTarget = "{color.accent}"),
      /minimumHitTarget needs a dimension token/,
    ],
  ];
  for (const [name, change, message] of failures) {
    test(`rejects ${name}`, () => assert.rejects(loadChip(change), message));
  }

  test("rejects a spec whose file is not its kebab-case name", () =>
    assert.rejects(
      loadSpecs({ "chips.yaml": chip() }),
      /must be in chip\.yaml/,
    ));

  test("rejects a specimen id another spec already uses", async () => {
    const first = chip();
    first.specimens[0].id = "chip-group-tones";
    const second = chip();
    second.name = "ChipGroup";
    second.specimens = [{ id: "chip-group-tones", description: "Every tone." }];
    await assert.rejects(
      loadSpecs({ "chip.yaml": first, "chip-group.yaml": second }),
      /chip\.yaml: specimen chip-group-tones is already used by .*chip-group\.yaml/,
    );
  });

  test("rejects YAML that does not parse", () =>
    assert.rejects(loadSpecs({ "chip.yaml": "name: [" }), /chip\.yaml/));
});
