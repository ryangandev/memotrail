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
  const requiredGroups = ["color", "font", "space", "radius", "motion"];

  for (const group of requiredGroups) {
    if (!value[group]) throw new Error(`Missing token group: ${group}`);
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
  const spacingLines = swiftNumberTokens("MTSpacing", value.space);
  const radiusLines = swiftNumberTokens("MTRadius", value.radius);
  const motionLines = Object.entries(value.motion).map(
    ([name, milliseconds]) =>
      `  static let ${swiftName(name)} = Double(${milliseconds}) / 1_000`,
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

enum MTColor {
${colorLines.join("\n")}
}

enum MTTypography {
${typographyLines.join("\n")}
}

enum MTSpacing {
${spacingLines.join("\n")}
}

enum MTRadius {
${radiusLines.join("\n")}
}

enum MTMotion {
${motionLines.join("\n")}
}

private extension Color {
  init(lightHex: String, darkHex: String) {
    self.init(
      uiColor: UIColor { traits in
        UIColor(hex: traits.userInterfaceStyle == .dark ? darkHex : lightHex)
      }
    )
  }
}

private extension UIColor {
  convenience init(hex: String) {
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
