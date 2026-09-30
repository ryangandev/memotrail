import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const packageRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const repositoryRoot = resolve(packageRoot, "../..");
const tokenPath = resolve(packageRoot, "tokens.json");
const webOutputPath = resolve(
  repositoryRoot,
  "apps/web/src/styles/generated-tokens.css",
);
const swiftOutputPath = resolve(
  repositoryRoot,
  "apps/ios/MemoTrail/DesignSystem/Generated/DesignTokens.swift",
);
const checkOnly = process.argv.includes("--check");

const tokens = JSON.parse(await readFile(tokenPath, "utf8"));

validateTokens(tokens);

const outputs = [
  [webOutputPath, makeCss(tokens)],
  [swiftOutputPath, makeSwift(tokens)],
];

if (checkOnly) {
  const stale = [];

  for (const [path, expected] of outputs) {
    try {
      const actual = await readFile(path, "utf8");
      if (actual !== expected) stale.push(path);
    } catch {
      stale.push(path);
    }
  }

  if (stale.length > 0) {
    throw new Error(
      `Generated design tokens are missing or stale:\n${stale.join("\n")}\nRun pnpm tokens:generate.`,
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

function validateTokens(value) {
  const requiredGroups = [
    "color",
    "font",
    "space",
    "radius",
    "motion",
    "shadow",
  ];

  for (const group of requiredGroups) {
    if (!value[group]) throw new Error(`Missing token group: ${group}`);
  }

  for (const [name, shadow] of Object.entries(value.shadow)) {
    shadowLayers(name, shadow);
  }

  const lightNames = Object.keys(value.color.light).sort();
  const darkNames = Object.keys(value.color.dark).sort();

  if (lightNames.join(",") !== darkNames.join(",")) {
    throw new Error("Light and dark color token names must match.");
  }

  for (const [mode, colors] of Object.entries(value.color)) {
    for (const [name, hex] of Object.entries(colors)) {
      if (!/^#[0-9A-F]{6}$/i.test(hex)) {
        throw new Error(`Invalid ${mode} color ${name}: ${hex}`);
      }
    }
  }
}

function makeCss(value) {
  const header =
    "/* Generated from packages/design-tokens/tokens.json. Do not edit directly. */";
  const base = [
    ...cssVariables("font-family", value.font.family, (entry) => entry),
    ...cssVariables("font-size", value.font.size, (entry) => `${entry}px`),
    ...cssVariables("line-height", value.font.lineHeight, (entry) => entry),
    ...cssVariables("font-weight", value.font.weight, (entry) => entry),
    ...cssVariables("space", value.space, (entry) => `${entry}px`),
    ...cssVariables("radius", value.radius, (entry) => `${entry}px`),
    ...cssVariables("motion", value.motion, (entry) => `${entry}ms`),
    ...cssVariables("shadow", value.shadow, (entry) => entry),
  ];
  const light = colorVariables(value.color.light);
  const dark = colorVariables(value.color.dark);

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

function makeSwift(value) {
  const colorLines = Object.keys(value.color.light).map(
    (name) =>
      `  static let ${name} = Color(lightHex: "${value.color.light[name]}", darkHex: "${value.color.dark[name]}")`,
  );
  const colorCatalogLines = Object.keys(value.color.light).map((name) =>
    swiftCall(4, "MTColorToken", [
      `name: "${name}"`,
      `lightHex: "${value.color.light[name]}"`,
      `darkHex: "${value.color.dark[name]}"`,
      `color: ${name}`,
    ]),
  );
  const spacingLines = swiftNumberTokens("MTSpacing", value.space);
  const radiusLines = swiftNumberTokens("MTRadius", value.radius);
  const motionLines = Object.entries(value.motion).map(
    ([name, milliseconds]) =>
      `  static let ${swiftName(name)} = Double(${milliseconds}) / 1_000`,
  );
  const lineHeightLines = Object.entries(value.font.lineHeight).map(
    ([name, multiplier]) =>
      `  static let ${swiftName(name)}: CGFloat = ${multiplier}`,
  );
  const shadowLines = Object.entries(value.shadow).flatMap(([name, shadow]) => {
    const layers = shadowLayers(name, shadow);
    return [
      `  static let ${swiftName(name)} = [`,
      ...layers.map((layer) =>
        swiftCall(
          4,
          "MTShadowLayer",
          [
            `red: ${layer.red}`,
            `green: ${layer.green}`,
            `blue: ${layer.blue}`,
            `opacity: ${layer.opacity}`,
            `radius: ${layer.radius}`,
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
  const shadowCatalogLines = Object.entries(value.shadow).map(
    ([name, shadow]) =>
      swiftCall(4, "MTShadowToken", [
        `name: "${name}"`,
        `css: ${JSON.stringify(shadow)}`,
        `layers: ${swiftName(name)}`,
      ]),
  );
  const typographyLines = [
    `  static let display = Font.system(size: ${value.font.size.display}, weight: .medium, design: .serif)`,
    `  static let title = Font.system(size: ${value.font.size.title}, weight: .medium, design: .serif)`,
    `  static let titleSmall = Font.system(size: ${value.font.size.titleSmall}, weight: .semibold)`,
    `  static let bodyLarge = Font.system(size: ${value.font.size.bodyLarge})`,
    `  static let body = Font.system(size: ${value.font.size.body})`,
    `  static let label = Font.system(size: ${value.font.size.label}, weight: .medium)`,
    `  static let caption = Font.system(size: ${value.font.size.caption}, weight: .medium)`,
  ];

  return `// Generated from packages/design-tokens/tokens.json. Do not edit directly.

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
${swiftCatalog(value.space, (name) => (/^\d/.test(name) ? `s${name}` : swiftName(name)))}
  ]
}

enum MTRadius {
${radiusLines.join("\n")}

  static let catalog: [(name: String, value: CGFloat)] = [
${swiftCatalog(value.radius, swiftName)}
  ]
}

enum MTMotion {
${motionLines.join("\n")}

  static let catalog: [(name: String, seconds: Double)] = [
${swiftCatalog(value.motion, swiftName)}
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

function shadowLayers(name, shadow) {
  const layers = shadow.split(/,(?![^(]*\))/).map((layer) => layer.trim());

  return layers.map((layer) => {
    const match = layer.match(
      /^(-?\d+(?:\.\d+)?)(?:px)? (-?\d+(?:\.\d+)?)(?:px)? (\d+(?:\.\d+)?)(?:px)? rgb\((\d{1,3}) (\d{1,3}) (\d{1,3}) \/ (0|1|0?\.\d+)\)$/,
    );

    if (!match) throw new Error(`Invalid shadow ${name}: ${layer}`);

    const [, x, y, blur, red, green, blue, opacity] = match;
    return {
      blue: Number(blue),
      green: Number(green),
      opacity: Number(opacity),
      radius: Number(blur) / 2,
      red: Number(red),
      x: Number(x),
      y: Number(y),
    };
  });
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

function swiftCatalog(entries, identifier) {
  return Object.keys(entries)
    .map((name) => `    ("${name}", ${identifier(name)}),`)
    .join("\n");
}

function cssVariables(group, entries, transform) {
  return Object.entries(entries).map(
    ([name, value]) => `--mt-${group}-${kebabCase(name)}: ${transform(value)};`,
  );
}

function colorVariables(entries) {
  return cssVariables("color", entries, (value) => value);
}

function swiftNumberTokens(group, entries) {
  return Object.entries(entries).map(([name, value]) => {
    const identifier = /^\d/.test(name) ? `s${name}` : swiftName(name);
    return `  static let ${identifier}: CGFloat = ${value}`;
  });
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
