import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

// Reads the DTCG 2025.10 resolver in tokens/, resolves the light and dark themes, and writes
// the Web CSS variables, the Web gallery catalog, and the Swift tokens.

const packageRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const repositoryRoot = resolve(packageRoot, "../..");
const tokenDirectory = resolve(packageRoot, "tokens");
const resolverPath = resolve(tokenDirectory, "soft-ledger.resolver.json");
const sourceLabel = relative(repositoryRoot, tokenDirectory);
const webCssPath = resolve(
  repositoryRoot,
  "apps/web/src/styles/generated-tokens.css",
);
const webCatalogPath = resolve(
  repositoryRoot,
  "apps/web/src/generated/design-tokens.json",
);
const swiftOutputPath = resolve(
  repositoryRoot,
  "apps/ios/MemoTrail/DesignSystem/Generated/DesignTokens.swift",
);
const checkOnly = process.argv.includes("--check");

// Platform outputs never receive palette tokens, so components can only use semantic roles.
const privateGroups = new Set(["palette"]);
const themeModifier = "theme";
const themes = ["light", "dark"];

async function main() {
  const resolver = await readJson(resolverPath);
  const system = await resolveSystem(resolver);

  const outputs = [
    [webCssPath, makeCss(system)],
    [webCatalogPath, makeCatalog(system)],
    [swiftOutputPath, makeSwift(system)],
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

    console.log("Generated design tokens are current.");
  } else {
    for (const [path, contents] of outputs) {
      await mkdir(dirname(path), { recursive: true });
      await writeFile(path, contents, "utf8");
    }

    console.log("Generated Web and Swift design tokens.");
  }
}

// Resolution

async function resolveSystem(document) {
  if (document.version !== "2025.10") {
    throw new Error(
      `Resolver version must be "2025.10", got ${JSON.stringify(document.version)}.`,
    );
  }

  const modifier = document.modifiers?.[themeModifier];
  const contexts = Object.keys(modifier?.contexts ?? {});
  if (contexts.sort().join(",") !== [...themes].sort().join(",")) {
    throw new Error(
      `The "${themeModifier}" modifier must define exactly the contexts ${themes.join(" and ")}.`,
    );
  }

  const resolved = {};
  const themed = {};

  for (const theme of themes) {
    const { documents, contextDocuments } = await orderedDocuments(document, {
      [themeModifier]: theme,
    });
    resolved[theme] = resolveTokens(
      flatten(documents.reduce(mergeDocuments, {})),
    );
    themed[theme] = [
      ...flatten(contextDocuments.reduce(mergeDocuments, {})).keys(),
    ];
  }

  const [first, ...others] = themes;
  for (const theme of others) {
    if (themed[theme].join(",") !== themed[first].join(",")) {
      throw new Error(
        `The ${first} and ${theme} themes must define the same tokens in the same order.`,
      );
    }
    for (const [path, token] of resolved[first]) {
      if (resolved[theme].get(path)?.type !== token.type) {
        throw new Error(
          `Token {${path}} must have the same type in every theme.`,
        );
      }
    }
  }

  const themedPaths = new Set(themed[first]);
  const isPublic = (path) => !privateGroups.has(path.split(".")[0]);

  return {
    name: document.name,
    shared: [...resolved[first]].filter(
      ([path]) => isPublic(path) && !themedPaths.has(path),
    ),
    themed: Object.fromEntries(
      themes.map((theme) => [
        theme,
        [...resolved[theme]].filter(
          ([path]) => isPublic(path) && themedPaths.has(path),
        ),
      ]),
    ),
  };
}

async function orderedDocuments(document, input) {
  const documents = [];
  const contextDocuments = [];

  for (const entry of document.resolutionOrder ?? []) {
    const { kind, name, definition } = resolutionEntry(document, entry);

    if (kind === "set") {
      documents.push(...(await loadSources(definition.sources, `set ${name}`)));
      continue;
    }

    const context = input[name] ?? definition.default;
    const sources = definition.contexts?.[context];
    if (!sources) {
      throw new Error(`Modifier ${name} has no context ${context}.`);
    }

    const loaded = await loadSources(sources, `modifier ${name}`);
    documents.push(...loaded);
    if (name === themeModifier) contextDocuments.push(...loaded);
  }

  if (documents.length === 0) {
    throw new Error("The resolver's resolutionOrder selects no tokens.");
  }

  return { documents, contextDocuments };
}

function resolutionEntry(document, entry) {
  if (typeof entry.$ref === "string") {
    const match = entry.$ref.match(/^#\/(sets|modifiers)\/([^/]+)$/);
    const definition = match && document[match[1]]?.[match[2]];
    if (!definition) {
      throw new Error(`Unknown resolutionOrder reference ${entry.$ref}.`);
    }
    return {
      kind: match[1] === "sets" ? "set" : "modifier",
      name: match[2],
      definition,
    };
  }

  if (entry.type === "set" || entry.type === "modifier") {
    return { kind: entry.type, name: entry.name, definition: entry };
  }

  throw new Error(`Invalid resolutionOrder entry ${JSON.stringify(entry)}.`);
}

async function loadSources(sources, owner) {
  if (!Array.isArray(sources)) {
    throw new Error(`The sources of ${owner} must be an array.`);
  }

  return Promise.all(
    sources.map((source) => {
      if (typeof source.$ref !== "string") return source;
      if (source.$ref.includes("#")) {
        throw new Error(
          `${owner}: file fragments are not supported (${source.$ref}).`,
        );
      }
      return readJson(resolve(tokenDirectory, source.$ref));
    }),
  );
}

// Later sources replace earlier tokens whole; groups merge key by key.
function mergeDocuments(target, source) {
  const merged = { ...target };

  for (const [key, value] of Object.entries(source)) {
    const existing = merged[key];
    merged[key] =
      isGroup(existing) && isGroup(value)
        ? mergeDocuments(existing, value)
        : value;
  }

  return merged;
}

function isGroup(value) {
  return isObject(value) && !("$value" in value);
}

const groupProperties = new Set([
  "$type",
  "$description",
  "$extensions",
  "$deprecated",
]);
const tokenProperties = new Set([...groupProperties, "$value"]);

function flatten(node, path = [], inheritedType) {
  const tokens = new Map();
  const type = node.$type ?? inheritedType;

  for (const key of Object.keys(node)) {
    if (key.startsWith("$") && !groupProperties.has(key)) {
      throw new Error(
        `${describePath(path)}: ${key} is not supported in token groups.`,
      );
    }
  }

  for (const [name, child] of Object.entries(node)) {
    if (name.startsWith("$")) continue;
    if (/[{}.]/.test(name)) {
      throw new Error(
        `${describePath(path)}: token and group names cannot contain {, }, or . (${name}).`,
      );
    }
    if (!isObject(child)) {
      throw new Error(
        `${describePath([...path, name])} must be a token or a group.`,
      );
    }

    const childPath = [...path, name];

    if (!("$value" in child)) {
      for (const [nestedPath, token] of flatten(child, childPath, type)) {
        tokens.set(nestedPath, token);
      }
      continue;
    }

    for (const key of Object.keys(child)) {
      if (!tokenProperties.has(key)) {
        throw new Error(
          `${describePath(childPath)}: ${key} is not a token property.`,
        );
      }
    }

    const tokenType = child.$type ?? type;
    if (!tokenType) {
      throw new Error(`${describePath(childPath)} has no $type.`);
    }

    tokens.set(childPath.join("."), { type: tokenType, value: child.$value });
  }

  return tokens;
}

function resolveTokens(tokens) {
  const resolved = new Map();
  const resolving = new Set();

  const resolveToken = (path) => {
    const cached = resolved.get(path);
    if (cached) return cached;

    const token = tokens.get(path);
    if (!token) throw new Error(`Unknown token reference {${path}}.`);
    if (resolving.has(path)) {
      throw new Error(`Circular token reference through {${path}}.`);
    }

    resolving.add(path);
    const value = resolveValue(token.type, token.value, path);
    resolving.delete(path);

    const result = { type: token.type, value };
    resolved.set(path, result);
    return result;
  };

  const resolveValue = (type, value, path) => {
    const target = aliasPath(value);
    if (target) {
      const referenced = resolveToken(target);
      if (referenced.type !== type) {
        throw new Error(
          `{${path}} is a ${type} but references the ${referenced.type} {${target}}.`,
        );
      }
      return referenced.value;
    }

    const validate = validators[type];
    if (!validate) throw new Error(`{${path}} has unsupported type ${type}.`);
    return validate(value, path, (nested, nestedType) =>
      resolveValue(nestedType, nested, path),
    );
  };

  for (const path of tokens.keys()) resolveToken(path);

  // Keep source order so generated outputs follow the token files.
  return new Map([...tokens.keys()].map((path) => [path, resolved.get(path)]));
}

function aliasPath(value) {
  return typeof value === "string" ? value.match(/^\{([^{}]+)\}$/)?.[1] : null;
}

// Validators return normalized values: colors as 8-bit channels, lengths in px, durations in ms.
const validators = {
  color(value, path) {
    if (!isObject(value) || value.colorSpace !== "srgb") {
      throw new Error(`{${path}} must be an sRGB color object.`);
    }

    const { components, alpha = 1, hex } = value;
    if (
      !Array.isArray(components) ||
      components.length !== 3 ||
      !components.every((component) => isUnit(component))
    ) {
      throw new Error(`{${path}} needs three sRGB components from 0 to 1.`);
    }
    if (!isUnit(alpha)) throw new Error(`{${path}} alpha must be 0 to 1.`);

    const channels = components.map((component) => Math.round(component * 255));
    if (hex !== undefined && hex.toUpperCase() !== hexString(channels)) {
      throw new Error(
        `{${path}} hex ${hex} does not match its components (${hexString(channels)}).`,
      );
    }

    return { channels, alpha };
  },

  dimension(value, path) {
    if (!isObject(value) || !Number.isFinite(value.value)) {
      throw new Error(`{${path}} must be a dimension object.`);
    }
    if (value.unit !== "px") {
      throw new Error(
        `{${path}} uses ${value.unit}; Web and Swift outputs support px dimensions only.`,
      );
    }
    return value.value;
  },

  duration(value, path) {
    if (!isObject(value) || !Number.isFinite(value.value)) {
      throw new Error(`{${path}} must be a duration object.`);
    }
    if (value.unit === "ms") return value.value;
    if (value.unit === "s") return value.value * 1_000;
    throw new Error(`{${path}} duration unit must be ms or s.`);
  },

  number(value, path) {
    if (!Number.isFinite(value)) throw new Error(`{${path}} must be a number.`);
    return value;
  },

  fontWeight(value, path) {
    if (!Number.isInteger(value) || value < 1 || value > 1_000) {
      throw new Error(
        `{${path}} must be a numeric font weight from 1 to 1000.`,
      );
    }
    return value;
  },

  fontFamily(value, path) {
    const families = Array.isArray(value) ? value : [value];
    if (
      families.length === 0 ||
      !families.every((family) => typeof family === "string" && family)
    ) {
      throw new Error(`{${path}} must name one or more font families.`);
    }
    return families;
  },

  shadow(value, path, nested) {
    const layers = (Array.isArray(value) ? value : [value]).flatMap((layer) =>
      aliasPath(layer) ? nested(layer, "shadow") : [layer],
    );
    if (layers.length === 0) throw new Error(`{${path}} has no shadow layers.`);

    return layers.map((layer) => {
      if ("channels" in layer) return layer;
      if (!isObject(layer)) {
        throw new Error(`{${path}} shadow layers must be objects.`);
      }
      if (layer.inset) {
        throw new Error(`{${path}} inset shadows have no SwiftUI equivalent.`);
      }

      const spread = nested(layer.spread, "dimension");
      if (spread !== 0) {
        throw new Error(`{${path}} shadow spread has no SwiftUI equivalent.`);
      }

      return {
        ...nested(layer.color, "color"),
        x: nested(layer.offsetX, "dimension"),
        y: nested(layer.offsetY, "dimension"),
        blur: nested(layer.blur, "dimension"),
      };
    });
  },
};

// Web

function makeCss(value) {
  const header = `/* Generated from ${sourceLabel}. Do not edit directly. */`;
  const base = value.shared.map(cssDeclaration);
  const light = value.themed.light.map(cssDeclaration);
  const dark = value.themed.dark.map(cssDeclaration);

  return `${header}

:root {
${indent(base)}
}

:root,
[data-theme="light"] {
  color-scheme: light;
${indent(light)}
}

@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    color-scheme: dark;
${indent(dark, 4)}
  }
}

[data-theme="dark"] {
  color-scheme: dark;
${indent(dark)}
}
`;
}

function cssDeclaration([path, token]) {
  const name = path.split(".").map(kebabCase).join("-");
  return `--mt-${name}: ${cssValue(token)};`;
}

function cssValue({ type, value }) {
  switch (type) {
    case "color":
      return cssColor(value);
    case "dimension":
      return `${value}px`;
    case "duration":
      return `${value}ms`;
    case "fontFamily":
      return value.map(cssFontFamily).join(", ");
    case "shadow":
      return value
        .map(
          (layer) =>
            `${cssLength(layer.x)} ${cssLength(layer.y)} ${cssLength(layer.blur)} ${cssColor(layer)}`,
        )
        .join(", ");
    default:
      return String(value);
  }
}

function cssColor({ channels, alpha }) {
  return alpha === 1
    ? hexString(channels)
    : `rgb(${channels.join(" ")} / ${alpha})`;
}

function cssLength(value) {
  return value === 0 ? "0" : `${value}px`;
}

const unquotedFamilies = new Set([
  "-apple-system",
  "cursive",
  "emoji",
  "fangsong",
  "fantasy",
  "math",
  "monospace",
  "sans-serif",
  "serif",
  "system-ui",
  "ui-monospace",
  "ui-rounded",
  "ui-sans-serif",
  "ui-serif",
]);

function cssFontFamily(family) {
  return unquotedFamilies.has(family) || /^[A-Za-z]+$/.test(family)
    ? family
    : JSON.stringify(family);
}

// The development gallery lists every public token with its resolved value.
function makeCatalog(value) {
  const catalog = { name: value.name };

  for (const [path, token] of value.shared) {
    setPath(catalog, path.split("."), catalogValue(token));
  }
  for (const theme of themes) {
    for (const [path, token] of value.themed[theme]) {
      const [group, ...rest] = path.split(".");
      setPath(catalog, [group, theme, ...rest], catalogValue(token));
    }
  }

  return `${JSON.stringify(catalog, null, 2)}\n`;
}

function catalogValue(token) {
  return ["color", "fontFamily", "shadow"].includes(token.type)
    ? cssValue(token)
    : token.value;
}

function setPath(target, [key, ...rest], value) {
  if (rest.length === 0) {
    target[key] = value;
    return;
  }
  target[key] ??= {};
  setPath(target[key], rest, value);
}

// Swift

function makeSwift(value) {
  const shared = new Map(value.shared);
  const light = new Map(value.themed.light);
  const dark = new Map(value.themed.dark);
  const group = (name) => children(shared, name);
  const fontSize = (name) => requireToken(shared, `font.size.${name}`);

  const colors = [...light.keys()].map((path) => {
    if (!path.startsWith("color.") || path.split(".").length !== 2) {
      throw new Error(`Swift supports themed colors only, not {${path}}.`);
    }
    return {
      name: path.slice("color.".length),
      lightHex: hexString(light.get(path).value.channels),
      darkHex: hexString(dark.get(path).value.channels),
    };
  });
  const colorLines = colors.map(
    ({ name, lightHex, darkHex }) =>
      `  static let ${name} = Color(lightHex: "${lightHex}", darkHex: "${darkHex}")`,
  );
  const colorCatalogLines = colors.map(({ name, lightHex, darkHex }) =>
    swiftCall(4, "MTColorToken", [
      `name: "${name}"`,
      `lightHex: "${lightHex}"`,
      `darkHex: "${darkHex}"`,
      `color: ${name}`,
    ]),
  );
  const spacing = group("space");
  const radius = group("radius");
  const motion = group("motion");
  const spacingLines = swiftNumberTokens(spacing);
  const radiusLines = swiftNumberTokens(radius);
  const motionLines = motion.map(
    ([name, milliseconds]) =>
      `  static let ${swiftName(name)} = Double(${milliseconds}) / 1_000`,
  );
  const lineHeightLines = group("lineHeight").map(
    ([name, multiplier]) =>
      `  static let ${swiftName(name)}: CGFloat = ${multiplier}`,
  );
  const shadows = children(shared, "shadow", true);
  const shadowLines = shadows.flatMap(([name, token]) => {
    const layers = token.value;
    return [
      `  static let ${swiftName(name)} = [`,
      ...layers.map((layer) =>
        swiftCall(
          4,
          "MTShadowLayer",
          [
            `red: ${layer.channels[0]}`,
            `green: ${layer.channels[1]}`,
            `blue: ${layer.channels[2]}`,
            `opacity: ${layer.alpha}`,
            // CSS blur is twice the equivalent SwiftUI shadow radius.
            `radius: ${layer.blur / 2}`,
            `x: ${layer.x}`,
            `y: ${layer.y}`,
          ],
          // swift-format drops the trailing comma of a one-element array.
          layers.length > 1 ? "," : "",
        ),
      ),
      "  ]",
    ];
  });
  const shadowCatalogLines = shadows.map(([name, token]) =>
    swiftCall(4, "MTShadowToken", [
      `name: "${name}"`,
      `css: ${JSON.stringify(cssValue(token))}`,
      `layers: ${swiftName(name)}`,
    ]),
  );
  const typographyLines = [
    `  static let display = Font.system(size: ${fontSize("display")}, weight: .medium, design: .serif)`,
    `  static let title = Font.system(size: ${fontSize("title")}, weight: .medium, design: .serif)`,
    `  static let titleSmall = Font.system(size: ${fontSize("titleSmall")}, weight: .semibold)`,
    `  static let bodyLarge = Font.system(size: ${fontSize("bodyLarge")})`,
    `  static let body = Font.system(size: ${fontSize("body")})`,
    `  static let label = Font.system(size: ${fontSize("label")}, weight: .medium)`,
    `  static let caption = Font.system(size: ${fontSize("caption")}, weight: .medium)`,
  ];

  return `// Generated from ${sourceLabel}. Do not edit directly.

import SwiftUI
import UIKit

struct MTColorToken: Sendable {
  let name: String
  let lightHex: String
  let darkHex: String
  let color: Color
}

enum MTColor {
${colorLines.join("\n")}

  static let catalog = [
${colorCatalogLines.join("\n")}
  ]
}

enum MTTypography {
${typographyLines.join("\n")}
}

enum MTSpacing {
${spacingLines.join("\n")}

  static let catalog: [(name: String, value: CGFloat)] = [
${swiftCatalog(spacing)}
  ]
}

enum MTRadius {
${radiusLines.join("\n")}

  static let catalog: [(name: String, value: CGFloat)] = [
${swiftCatalog(radius)}
  ]
}

enum MTMotion {
${motionLines.join("\n")}

  static let catalog: [(name: String, seconds: Double)] = [
${swiftCatalog(motion)}
  ]
}

enum MTLineHeight {
${lineHeightLines.join("\n")}
}

struct MTShadowLayer: Sendable {
  let color: Color
  let radius: CGFloat
  let x: CGFloat
  let y: CGFloat

  init(
    red: Double, green: Double, blue: Double, opacity: Double, radius: CGFloat, x: CGFloat,
    y: CGFloat
  ) {
    color = Color(red: red / 255, green: green / 255, blue: blue / 255).opacity(opacity)
    self.radius = radius
    self.x = x
    self.y = y
  }
}

struct MTShadowToken: Sendable {
  let name: String
  let css: String
  let layers: [MTShadowLayer]
}

// CSS blur is twice the equivalent SwiftUI shadow radius.
enum MTShadow {
${shadowLines.join("\n")}

  static let catalog = [
${shadowCatalogLines.join("\n")}
  ]
}

extension Color {
  fileprivate init(lightHex: String, darkHex: String) {
    self.init(
      uiColor: UIColor { traits in
        UIColor(hex: traits.userInterfaceStyle == .dark ? darkHex : lightHex)
      }
    )
  }
}

extension UIColor {
  fileprivate convenience init(hex: String) {
    var value: UInt64 = 0
    Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&value)
    self.init(
      red: CGFloat((value >> 16) & 0xFF) / 255,
      green: CGFloat((value >> 8) & 0xFF) / 255,
      blue: CGFloat(value & 0xFF) / 255,
      alpha: 1
    )
  }
}
`;
}

// Direct children of a group as [name, value] pairs, or [name, token] with whole tokens.
function children(tokens, group, wholeTokens = false) {
  const prefix = `${group}.`;
  return [...tokens]
    .filter(
      ([path]) =>
        path.startsWith(prefix) && !path.slice(prefix.length).includes("."),
    )
    .map(([path, token]) => [
      path.slice(prefix.length),
      wholeTokens ? token : token.value,
    ]);
}

function requireToken(tokens, path) {
  const token = tokens.get(path);
  if (!token) throw new Error(`Swift typography needs the token {${path}}.`);
  return token.value;
}

// Emits a call the way swift-format prints it: on one line when it fits in 100 columns,
// otherwise with its arguments packed onto continuation lines two spaces deeper.
function swiftCall(indentation, name, args, suffix = ",") {
  const prefix = " ".repeat(indentation);
  const single = `${prefix}${name}(${args.join(", ")})${suffix}`;
  if (single.length <= 100) return single;

  const continuation = " ".repeat(indentation + 2);
  const lines = [`${prefix}${name}(`];
  let packed = [];
  args.forEach((arg, index) => {
    const ending = index === args.length - 1 ? `)${suffix}` : ",";
    const line = `${continuation}${[...packed, arg].join(", ")}${ending}`;
    if (packed.length > 0 && line.length > 100) {
      lines.push(`${continuation}${packed.join(", ")},`);
      packed = [];
    }
    packed.push(arg);
  });
  lines.push(`${continuation}${packed.join(", ")})${suffix}`);
  return lines.join("\n");
}

function swiftCatalog(entries) {
  return entries
    .map(([name]) => `    ("${name}", ${swiftIdentifier(name)}),`)
    .join("\n");
}

function swiftNumberTokens(entries) {
  return entries.map(
    ([name, value]) =>
      `  static let ${swiftIdentifier(name)}: CGFloat = ${value}`,
  );
}

function swiftIdentifier(name) {
  return /^\d/.test(name) ? `s${name}` : swiftName(name);
}

// Helpers

async function readJson(path) {
  try {
    return JSON.parse(await readFile(path, "utf8"));
  } catch (error) {
    throw new Error(
      `Cannot read ${relative(repositoryRoot, path)}: ${error.message}`,
    );
  }
}

function isObject(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isUnit(value) {
  return Number.isFinite(value) && value >= 0 && value <= 1;
}

function hexString(channels) {
  return `#${channels
    .map((channel) => channel.toString(16).padStart(2, "0"))
    .join("")
    .toUpperCase()}`;
}

function describePath(path) {
  return path.length === 0 ? "The token document" : `{${path.join(".")}}`;
}

function kebabCase(value) {
  return value.replace(/([a-z0-9])([A-Z])/g, "$1-$2").toLowerCase();
}

function swiftName(value) {
  return value.replace(/-([a-z])/g, (_, letter) => letter.toUpperCase());
}

function indent(lines, spaces = 2) {
  const prefix = " ".repeat(spaces);
  return lines.map((line) => `${prefix}${line}`).join("\n");
}

// Runs last so every declaration above is initialized.
await main();
