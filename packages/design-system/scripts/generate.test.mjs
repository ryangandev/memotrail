import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { describe, test } from "node:test";
import { fileURLToPath } from "node:url";
import { checkContrast, contrastRatio } from "./lib/contrast.mjs";
import { validateIcons } from "./lib/icons.mjs";
import { readJson, resolveSystem } from "./lib/resolve.mjs";
import { makeSwift } from "./lib/swift.mjs";
import { makeCatalog, makeCss, makeTypeScript } from "./lib/web.mjs";

const packageRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const tokenDirectory = resolve(packageRoot, "tokens");

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
