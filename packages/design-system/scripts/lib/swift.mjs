import { iosTextStyles, isPublic } from "./resolve.mjs";
import { cssValue, orderedPaths, textCase } from "./web.mjs";
import {
  camelCase,
  deepEqual,
  formatNumber,
  hexString,
  pascalCase,
} from "./util.mjs";

// Writes DesignTokens.swift. Every public iOS token must land somewhere in this file, so a new
// group fails loudly until it has a Swift shape.

const fontWeights = {
  100: "ultraLight",
  200: "thin",
  300: "light",
  400: "regular",
  500: "medium",
  600: "semibold",
  700: "bold",
  800: "heavy",
  900: "black",
};
const fontDesigns = { sans: "default", serif: "serif", mono: "monospaced" };
const systemMaterials = {
  ultraThin: "ultraThinMaterial",
  thin: "thinMaterial",
  regular: "regularMaterial",
  thick: "thickMaterial",
  ultraThick: "ultraThickMaterial",
  bar: "bar",
};
const swiftKeywords = new Set([
  "as",
  "break",
  "case",
  "class",
  "continue",
  "default",
  "defer",
  "do",
  "else",
  "enum",
  "extension",
  "fallthrough",
  "false",
  "for",
  "func",
  "guard",
  "if",
  "import",
  "in",
  "init",
  "is",
  "let",
  "nil",
  "operator",
  "private",
  "protocol",
  "public",
  "repeat",
  "return",
  "self",
  "static",
  "struct",
  "subscript",
  "super",
  "switch",
  "throw",
  "true",
  "try",
  "var",
  "where",
  "while",
]);

export function makeSwift(system, icons, sourceLabel) {
  const light = system.platforms.ios.light;
  const dark = system.platforms.ios.dark;
  const paths = orderedPaths(light);
  const emitted = new Set();
  const token = (path) => {
    emitted.add(path);
    return light.get(path);
  };
  const under = (prefix) =>
    paths.filter((path) => path.startsWith(`${prefix}.`));
  const children = (prefix) =>
    under(prefix).filter(
      (path) => !path.slice(prefix.length + 1).includes("."),
    );

  for (const path of paths) {
    const { type } = light.get(path);
    if (
      !["color", "shadow"].includes(type) &&
      !deepEqual(light.get(path).value, dark.get(path).value)
    ) {
      throw new Error(
        `{${path}} differs by theme; Swift supports theme-dependent colors only.`,
      );
    }
  }

  const color = (path) => swiftColor(path, light, dark);

  // Colors
  const colorPaths = under("color");
  const colorEntries = colorPaths.map((path) => {
    token(path);
    return { path, name: camelCase(path.split(".").slice(1)) };
  });
  const colorLines = colorEntries.map(({ path, name }) =>
    swiftCall(
      2,
      `static let ${name} = ${color(path).callee}`,
      color(path).args,
      "",
    ),
  );
  const colorCatalogLines = colorEntries.map(({ path, name }) => {
    const { lightHex, darkHex, lightOpacity, darkOpacity } = colorValues(
      path,
      light,
      dark,
    );
    return swiftCall(4, "MTColorToken", [
      `name: "${name}"`,
      `lightHex: "${lightHex}"`,
      `darkHex: "${darkHex}"`,
      ...(lightOpacity === 1 && darkOpacity === 1
        ? []
        : [`lightOpacity: ${lightOpacity}`, `darkOpacity: ${darkOpacity}`]),
      `color: ${name}`,
    ]);
  });

  // Text roles
  for (const path of [
    ...under("font.size"),
    ...under("font.family"),
    ...under("font.weight"),
  ]) {
    // Text roles consume the font families, sizes, and weights.
    emitted.add(path);
  }

  const roles = children("type").map((path) => textRole(token(path)));
  const roleLines = roles.flatMap((role) => [
    swiftCall(
      2,
      `static let ${role.name} = MTTextRole`,
      [
        `name: "${role.name}"`,
        `size: ${formatNumber(role.size)}`,
        `weight: .${role.weight}`,
        `design: .${role.design}`,
        `lineHeight: ${formatNumber(role.lineHeight)}`,
        `tracking: ${formatNumber(role.tracking)}`,
        `isUppercase: ${role.isUppercase}`,
        `textStyle: ${role.textStyle ? `.${role.textStyle}` : "nil"}`,
        `font: ${role.font ? `MTFont.${role.name}` : "nil"}`,
      ],
      "",
    ),
  ]);
  const fontLines = roles.flatMap((role) => {
    if (role.scaled) {
      return [
        ...(role.description ? [`  // ${role.description}`] : []),
        `  // ${role.name} scales a custom ${formatNumber(role.size)} pt size with ${role.textStyle}, so it has no`,
        `  // static font; apply it with mtTextRole(.${role.name}).`,
      ];
    }
    return [
      ...(role.description ? [`  /// ${role.description}`] : []),
      `  static let ${role.name} = ${role.font}`,
    ];
  });

  // Scales
  // Ordered by size: JavaScript lists whole-number keys before fractional steps like 1-5.
  const spacing = children("space")
    .map((path) => [path.split(".")[1], token(path).value])
    .sort((a, b) => a[1] - b[1]);
  const radius = children("radius").map((path) => [
    path.split(".")[1],
    token(path).value,
  ]);
  const motion = children("motion")
    .filter((path) => light.get(path).type === "duration")
    .map((path) => [path.split(".")[1], token(path).value]);
  const lineHeights = children("lineHeight").map((path) => [
    path.split(".")[1],
    token(path).value,
  ]);
  const easings = under("motion.easing").map((path) => [
    path.split(".").at(-1),
    token(path).value,
  ]);
  const easingLines = easings.map(([name, [x1, y1, x2, y2]]) =>
    swiftCall(
      2,
      `static let ${swiftIdentifier(name)} = MTEasingCurve`,
      [
        `name: "${name}"`,
        `x1: ${formatNumber(x1)}`,
        `y1: ${formatNumber(y1)}`,
        `x2: ${formatNumber(x2)}`,
        `y2: ${formatNumber(y2)}`,
      ],
      "",
    ),
  );

  // Shadows
  const shadows = children("shadow").map((path) => [
    path.split(".")[1],
    token(path).value,
  ]);
  const shadowLines = shadows.flatMap(([name, layers]) => [
    `  static let ${swiftIdentifier(name)} = ${shadowArray(layers, 2)}`,
  ]);
  const shadowCatalogLines = shadows.map(([name]) =>
    swiftCall(4, "MTShadowToken", [
      `name: "${name}"`,
      `css: ${JSON.stringify(cssValue(light.get(`shadow.${name}`)))}`,
      `layers: ${swiftIdentifier(name)}`,
    ]),
  );

  // Page widths
  const pageWidths = children("layout.pageWidth").map((path) => {
    const width = token(path);
    if (!width.description) {
      throw new Error(
        `{${path}} needs a $description; Swift uses it as the width's purpose.`,
      );
    }
    return {
      name: path.split(".").at(-1),
      value: width.value,
      purpose: width.description,
    };
  });

  // Nested constant groups
  const constantGroup = (name, prefix, skip = () => false) => {
    const members = under(prefix).filter((path) => !skip(path));
    for (const path of members) token(path);
    return nestedEnum(
      name,
      members.map((path) => [path.slice(prefix.length + 1).split("."), path]),
      (path) => constantValue(path, light, dark),
    );
  };
  const sizeLines = constantGroup("MTSize", "size");
  const layoutLines = constantGroup("MTLayout", "layout", (path) =>
    path.startsWith("layout.pageWidth."),
  );
  const stateLines = constantGroup("MTState", "state");

  // Materials
  const materialNames = [
    ...new Set(under("material").map((path) => path.split(".")[1])),
  ];
  const materials = materialNames.map((name) => {
    const parts = under(`material.${name}`);
    for (const path of parts) token(path);
    const allowed = new Set([
      `material.${name}.tint`,
      `material.${name}.border`,
    ]);
    const extra = parts.find((path) => !allowed.has(path));
    if (extra) {
      throw new Error(
        `{${extra}} has no Swift shape; native materials take a tint and an optional border. Mark it Web-only.`,
      );
    }
    if (!parts.includes(`material.${name}.tint`)) {
      throw new Error(`{material.${name}} needs a tint on iOS.`);
    }
    const systemMaterial = system.groups.get(`material.${name}`)?.ios?.material;
    return swiftCall(
      2,
      `static let ${name} = MTMaterialToken`,
      [
        `name: "${name}"`,
        `tint: ${color(`material.${name}.tint`).expression}`,
        `border: ${parts.includes(`material.${name}.border`) ? color(`material.${name}.border`).expression : "nil"}`,
        `systemMaterial: ${systemMaterial ? `.${systemMaterial}` : "nil"}`,
      ],
      "",
    );
  });

  // Elevation
  const elevationNames = [
    ...new Set(under("elevation").map((path) => path.split(".")[1])),
  ];
  const elevations = elevationNames.map((name) => {
    const parts = under(`elevation.${name}`);
    for (const path of parts) token(path);
    const known = ["surface", "shadow", "scrim"].map(
      (part) => `elevation.${name}.${part}`,
    );
    const extra = parts.find((path) => !known.includes(path));
    if (extra) {
      throw new Error(
        `{${extra}} is not an elevation part; use surface, shadow, and scrim.`,
      );
    }
    if (!parts.includes(known[0])) {
      throw new Error(`{elevation.${name}} needs a surface.`);
    }
    return swiftCall(
      2,
      `static let ${name} = MTElevationToken`,
      [
        `name: "${name}"`,
        `surface: ${color(known[0]).expression}`,
        `shadow: ${parts.includes(known[1]) ? shadowExpression(known[1], light) : "[]"}`,
        `scrim: ${parts.includes(known[2]) ? color(known[2]).expression : "nil"}`,
      ],
      "",
    );
  });

  // Icons
  const iosIcons = icons.icons.filter((icon) => icon.platforms.includes("ios"));
  const iconLines = iosIcons.map(
    (icon) => `  case ${swiftCase(icon.name)} = "${icon.sfSymbol}"`,
  );

  const missing = paths.filter((path) => !emitted.has(path));
  if (missing.length > 0) {
    throw new Error(
      `DesignTokens.swift has no place for ${missing.map((path) => `{${path}}`).join(", ")}. Give the group a Swift shape or mark the tokens Web-only.`,
    );
  }

  return `// Generated from ${sourceLabel}. Do not edit directly.

import SwiftUI
import UIKit

struct MTColorToken: Sendable {
  let name: String
  let lightHex: String
  let darkHex: String
  var lightOpacity = 1.0
  var darkOpacity = 1.0
  let color: Color
}

enum MTColor {
${colorLines.join("\n")}

  static let catalog = [
${colorCatalogLines.join("\n")}
  ]
}

/// A text role: the font, tracking, and case shared with the Web --mt-type-* variables.
struct MTTextRole: Sendable {
  let name: String
  let size: CGFloat
  let weight: Font.Weight
  let design: Font.Design
  let lineHeight: CGFloat
  let tracking: CGFloat
  let isUppercase: Bool
  /// The Dynamic Type style the size scales with, or nil for a fixed size.
  let textStyle: Font.TextStyle?
  /// The role's static MTFont, or nil when it scales a custom size with its text style.
  let font: Font?

${roleLines.join("\n")}

  static let catalog = [
${roles.map((role) => `    ${role.name},`).join("\n")}
  ]
}

// Text role fonts. Roles mapped to a Dynamic Type style follow it; the others keep a fixed size.
enum MTFont {
${fontLines.join("\n")}
}

enum MTSpacing {
${swiftNumberTokens(spacing).join("\n")}

  static let catalog: [(name: String, value: CGFloat)] = [
${swiftCatalog(spacing)}
  ]
}

enum MTRadius {
${swiftNumberTokens(radius).join("\n")}

  static let catalog: [(name: String, value: CGFloat)] = [
${swiftCatalog(radius)}
  ]
}

enum MTMotion {
${motion.map(([name, milliseconds]) => `  static let ${swiftIdentifier(name)} = Double(${milliseconds}) / 1_000`).join("\n")}

  static let catalog: [(name: String, seconds: Double)] = [
${swiftCatalog(motion)}
  ]
}

struct MTEasingCurve: Sendable {
  let name: String
  let x1: Double
  let y1: Double
  let x2: Double
  let y2: Double

  func animation(duration: Double) -> Animation {
    .timingCurve(x1, y1, x2, y2, duration: duration)
  }
}

enum MTEasing {
${easingLines.join("\n")}

  static let catalog = [
${easings.map(([name]) => `    ${swiftIdentifier(name)},`).join("\n")}
  ]
}

enum MTLineHeight {
${lineHeights.map(([name, multiplier]) => `  static let ${swiftIdentifier(name)}: CGFloat = ${multiplier}`).join("\n")}
}

${sizeLines.join("\n")}

${layoutLines.join("\n")}

// Page widths match the Web PageFrame variants; phones use the full width with page gutters.
enum MTPageWidth: CGFloat, CaseIterable, Sendable {
${pageWidths.map(({ name, value }) => `  case ${swiftCase(name)} = ${value}`).join("\n")}

  var title: String {
    switch self {
${pageWidths.map(({ name }) => `    case .${name}: "${pascalCase(name)}"`).join("\n")}
    }
  }

  var purpose: String {
    switch self {
${pageWidths.map(({ name, purpose }) => `    case .${name}: ${JSON.stringify(purpose)}`).join("\n")}
    }
  }
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

${stateLines.join("\n")}

enum MTSystemMaterial: Sendable {
${Object.keys(systemMaterials)
  .map((name) => `  case ${name}`)
  .join("\n")}

  var material: Material {
    switch self {
${Object.entries(systemMaterials)
  .map(([name, material]) => `    case .${name}: .${material}`)
  .join("\n")}
    }
  }
}

/// A translucent surface: a tint over an optional system material, with an optional border.
struct MTMaterialToken: Sendable {
  let name: String
  let tint: Color
  let border: Color?
  let systemMaterial: MTSystemMaterial?
}

enum MTMaterial {
${materials.join("\n")}

  static let catalog = [
${materialNames.map((name) => `    ${name},`).join("\n")}
  ]
}

/// A surface and its shadow, with the scrim behind it for overlays.
struct MTElevationToken: Sendable {
  let name: String
  let surface: Color
  let shadow: [MTShadowLayer]
  let scrim: Color?
}

enum MTElevation {
${elevations.join("\n")}

  static let catalog = [
${elevationNames.map((name) => `    ${name},`).join("\n")}
  ]
}

// Semantic icons share the Web icon vocabulary and resolve to SF Symbols.
enum MTIcon: String, CaseIterable, Sendable {
${iconLines.join("\n")}

  var systemName: String { rawValue }

  /// Icons that only native iOS draws; Web has no glyph for them yet.
  static let iosOnly: Set<MTIcon> = [
${iosIcons
  .filter((icon) => !icon.platforms.includes("web"))
  .map((icon) => `    .${swiftCase(icon.name)},`)
  .join("\n")}
  ]
}

extension Color {
  fileprivate init(
    lightHex: String, darkHex: String, lightOpacity: Double = 1, darkOpacity: Double = 1
  ) {
    self.init(
      uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
          ? UIColor(hex: darkHex, alpha: darkOpacity) : UIColor(hex: lightHex, alpha: lightOpacity)
      }
    )
  }
}

extension UIColor {
  fileprivate convenience init(hex: String, alpha: Double) {
    var value: UInt64 = 0
    Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&value)
    self.init(
      red: CGFloat((value >> 16) & 0xFF) / 255,
      green: CGFloat((value >> 8) & 0xFF) / 255,
      blue: CGFloat(value & 0xFF) / 255,
      alpha: alpha
    )
  }
}
`;
}

function colorValues(path, light, dark) {
  const lightValue = light.get(path).value;
  const darkValue = dark.get(path).value;
  return {
    lightHex: hexString(lightValue.channels),
    darkHex: hexString(darkValue.channels),
    lightOpacity: lightValue.alpha,
    darkOpacity: darkValue.alpha,
  };
}

// A color as a Swift expression: a reference when the token aliases a public color, otherwise
// a light and dark pair.
function swiftColor(path, light, dark) {
  const lightToken = light.get(path);
  const darkToken = dark.get(path);
  const alias = lightToken.alias;
  if (
    alias &&
    alias === darkToken.alias &&
    isPublic(alias) &&
    alias.startsWith("color.") &&
    light.has(alias)
  ) {
    const reference = `MTColor.${camelCase(alias.split(".").slice(1))}`;
    return { expression: reference, callee: reference, args: null };
  }
  const { lightHex, darkHex, lightOpacity, darkOpacity } = colorValues(
    path,
    light,
    dark,
  );
  const args = [
    `lightHex: "${lightHex}"`,
    `darkHex: "${darkHex}"`,
    ...(lightOpacity === 1 && darkOpacity === 1
      ? []
      : [`lightOpacity: ${lightOpacity}`, `darkOpacity: ${darkOpacity}`]),
  ];
  return { expression: `Color(${args.join(", ")})`, callee: "Color", args };
}

function shadowExpression(path, light) {
  const shadow = light.get(path);
  if (shadow.alias && isPublic(shadow.alias) && light.has(shadow.alias)) {
    const [group, ...rest] = shadow.alias.split(".");
    if (group === "shadow" && rest.length === 1)
      return `MTShadow.${swiftIdentifier(rest[0])}`;
  }
  return shadowArray(shadow.value, 4);
}

function shadowArray(layers, indentation) {
  const pad = " ".repeat(indentation);
  return [
    "[",
    ...layers.map((layer) =>
      swiftCall(
        indentation + 2,
        "MTShadowLayer",
        [
          `red: ${layer.channels[0]}`,
          `green: ${layer.channels[1]}`,
          `blue: ${layer.channels[2]}`,
          `opacity: ${formatNumber(layer.alpha)}`,
          // CSS blur is twice the equivalent SwiftUI shadow radius.
          `radius: ${formatNumber(layer.blur / 2)}`,
          `x: ${layer.x}`,
          `y: ${layer.y}`,
        ],
        // swift-format drops the trailing comma of a one-element array.
        layers.length > 1 ? "," : "",
      ),
    ),
    `${pad}]`,
  ].join("\n");
}

function constantValue(path, light, dark) {
  const token = light.get(path);
  switch (token.type) {
    case "color": {
      const color = swiftColor(path, light, dark);
      return color.args
        ? { callee: "Color", args: color.args }
        : { expression: color.expression };
    }
    case "dimension":
      return { type: "CGFloat", expression: formatNumber(token.value) };
    case "number":
      return { type: "Double", expression: formatNumber(token.value) };
    case "duration":
      return { expression: `Double(${token.value}) / 1_000` };
    case "shadow":
      return { expression: shadowExpression(path, light) };
    default:
      throw new Error(
        `{${path}} is a ${token.type}, which has no Swift constant shape.`,
      );
  }
}

// Emits nested enums for a token group: subgroups become PascalCase enums and tokens become
// static constants, in source order. Members are separated by a blank line around enums.
function nestedEnum(name, entries, value, depth = 0) {
  const pad = "  ".repeat(depth);
  const members = [];
  const seen = new Map();
  for (const [segments, path] of entries) {
    if (segments.length === 1) {
      members.push({ kind: "constant", name: segments[0], path });
      continue;
    }
    const [head, ...rest] = segments;
    if (!seen.has(head)) {
      const group = { kind: "enum", name: head, entries: [] };
      seen.set(head, group);
      members.push(group);
    }
    seen.get(head).entries.push([rest, path]);
  }

  const blocks = members.map((member) => {
    if (member.kind === "enum") {
      return nestedEnum(
        pascalCase(member.name),
        member.entries,
        value,
        depth + 1,
      );
    }
    const constant = value(member.path);
    const declaration = `static let ${swiftIdentifier(member.name)}`;
    if (constant.callee) {
      return [
        swiftCall(
          2 * (depth + 1),
          `${declaration} = ${constant.callee}`,
          constant.args,
          "",
        ),
      ];
    }
    return [
      `${pad}  ${declaration}${constant.type ? `: ${constant.type}` : ""} = ${constant.expression}`,
    ];
  });

  const lines = [`${pad}enum ${name} {`];
  blocks.forEach((block, index) => {
    const previous = members[index - 1];
    if (
      previous &&
      (previous.kind === "enum" || members[index].kind === "enum")
    ) {
      lines.push("");
    }
    lines.push(...block);
  });
  lines.push(`${pad}}`);
  return lines;
}

export function textRole(token) {
  const { value, extension } = token;
  const familyAlias = value.aliases.fontFamily;
  const family = familyAlias?.match(/^font\.family\.(\w+)$/)?.[1];
  const design = fontDesigns[family];
  if (!design) {
    throw new Error(
      `{${token.path}} font family must reference {font.family.sans}, {font.family.serif}, or {font.family.mono} so Swift can choose a font design.`,
    );
  }
  const weight = fontWeights[value.fontWeight];
  if (!weight) {
    throw new Error(
      `{${token.path}} weight ${value.fontWeight} has no SwiftUI Font.Weight.`,
    );
  }

  const name = token.path.split(".").at(-1);
  const styleName =
    extension.ios.textStyle === "none" ? null : extension.ios.textStyle;
  const style = styleName ? iosTextStyles[styleName] : null;
  const caseValue = extension.ios.textCase ?? textCase(token);
  if (!["none", "uppercase"].includes(caseValue)) {
    throw new Error(
      `{${token.path}} text case ${caseValue} has no SwiftUI equivalent.`,
    );
  }

  let font = null;
  if (!style) {
    const args = [`size: ${formatNumber(value.fontSize)}`];
    if (weight !== "regular") args.push(`weight: .${weight}`);
    if (design !== "default") args.push(`design: .${design}`);
    font = `Font.system(${args.join(", ")})`;
  } else if (style.size === value.fontSize) {
    const base =
      design === "default"
        ? `Font.${styleName}`
        : `Font.system(.${styleName}, design: .${design})`;
    font =
      value.fontWeight === style.weight ? base : `${base}.weight(.${weight})`;
  }

  return {
    name: swiftIdentifier(name),
    description: token.description,
    size: value.fontSize,
    weight,
    design,
    lineHeight: value.lineHeight,
    tracking: value.letterSpacing,
    isUppercase: caseValue === "uppercase",
    textStyle: styleName,
    scaled: Boolean(style) && style.size !== value.fontSize,
    font,
  };
}

// Emits a call the way swift-format prints it: on one line when it fits in 100 columns,
// otherwise with its arguments packed onto continuation lines two spaces deeper.
export function swiftCall(indentation, name, args, suffix = ",") {
  const prefix = " ".repeat(indentation);
  if (args === null) return `${prefix}${name}${suffix}`;
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

const swiftGroups = {
  color: "MTColor",
  elevation: "MTElevation",
  layout: "MTLayout",
  lineHeight: "MTLineHeight",
  material: "MTMaterial",
  radius: "MTRadius",
  shadow: "MTShadow",
  size: "MTSize",
  space: "MTSpacing",
  state: "MTState",
  type: "MTFont",
};

// The Swift expression that reads a token's value, the way DesignTokens.swift names it.
export function swiftReference(path) {
  const [group, ...rest] = path.split(".");
  if (group === "color") return `MTColor.${camelCase(rest)}`;
  if (group === "motion") {
    return rest[0] === "easing"
      ? `MTEasing.${swiftIdentifier(rest[1])}`
      : `MTMotion.${swiftIdentifier(rest[0])}`;
  }
  if (group === "layout" && rest[0] === "pageWidth") {
    return `MTPageWidth.${swiftCase(rest[1])}.rawValue`;
  }
  if (["material", "elevation"].includes(group)) {
    return `${swiftGroups[group]}.${rest[0]}`;
  }
  if (!swiftGroups[group]) return null;
  const enums = rest.slice(0, -1).map(pascalCase);
  return [swiftGroups[group], ...enums, swiftIdentifier(rest.at(-1))].join(".");
}

// Names that start with a digit get an s prefix, like MTSpacing.s4 and MTSize.Icon.s18, and a
// fractional step's hyphen becomes an underscore, like MTSpacing.s1_5.
function swiftIdentifier(name) {
  return /^\d/.test(name) ? `s${name.replaceAll("-", "_")}` : name;
}

function swiftCase(name) {
  return swiftKeywords.has(name) ? `\`${name}\`` : name;
}

// Writes ComponentVariants.swift: an enum per enum prop, a defaults enum per spec, and the
// specimens the iOS gallery shows. The app and its UI tests both compile it. A spec iOS does not
// implement emits nothing, so its specimens never reach the native gallery's list.
export function makeComponentSwift(allComponents, sourceLabel) {
  const components = allComponents.filter((spec) =>
    spec.implemented.includes("ios"),
  );
  // A spec without props on this platform has no types, only specimens.
  const blocks = components.flatMap((spec) => {
    const props = spec.props.filter((prop) => prop.platforms.includes("ios"));
    if (props.length === 0) return [];
    const lines = [
      `// ${spec.name}, from ${sourceLabel}/components/${spec.file}.`,
    ];
    for (const prop of props.filter(({ kind }) => kind === "enum")) {
      lines.push(
        "",
        ...docComment(prop.description, 0),
        `enum ${enumName(spec, prop)}: String, CaseIterable, Sendable {`,
        ...prop.values.map((value) => `  case ${swiftCase(value)}`),
        "}",
      );
    }
    lines.push(
      "",
      `/// ${spec.name} parameter defaults.`,
      `enum MT${spec.name}Defaults {`,
      ...props.map((prop) => {
        const value =
          prop.kind === "enum"
            ? `${enumName(spec, prop)}.${swiftCase(prop.default)}`
            : String(prop.default);
        return `  static let ${swiftCase(prop.names.ios)} = ${value}`;
      }),
      "}",
    );
    return lines.join("\n");
  });

  const specimens = components.flatMap((spec) =>
    spec.specimens.map((specimen) => ({
      ...specimen,
      component: spec.name,
      name: specimen.id.replace(/-([a-z0-9])/g, (_, letter) =>
        letter.toUpperCase(),
      ),
    })),
  );
  const switchLines = (property, value) => [
    `  var ${property}: String {`,
    "    switch self {",
    ...specimens.flatMap((specimen) =>
      switchCase(`.${swiftCase(specimen.name)}`, value(specimen)),
    ),
    "    }",
    "  }",
  ];

  return `// Generated from ${sourceLabel}/components. Do not edit directly.

${blocks.join("\n\n")}

/// A gallery specimen from a component spec. The Web gallery marks it with data-specimen and
/// the iOS gallery with \`accessibilityIdentifier\`, so UI tests find every specimen on both.
enum MTComponentSpecimen: String, CaseIterable, Sendable {
${specimens.map((specimen) => `  case ${swiftCase(specimen.name)} = "${specimen.id}"`).join("\n")}

  /// The component the specimen shows.
${switchLines("component", (specimen) => specimen.component).join("\n")}

  /// What the specimen shows, from its spec's description.
${switchLines("summary", (specimen) => specimen.description).join("\n")}

  var accessibilityIdentifier: String { "specimen-\\(rawValue)" }
}
`;
}

// Writes a switch case returning text within swift-format's 100 columns: on the case line,
// on its own line, or as a multiline literal whose lines a trailing backslash joins.
function switchCase(pattern, text) {
  if (/[\u0000-\u001f]/.test(text)) {
    throw new Error(`Swift strings cannot hold control characters: ${text}`);
  }
  const escaped = text.replaceAll("\\", "\\\\");
  const quoted = `"${escaped.replaceAll('"', '\\"')}"`;
  const caseLine = `    case ${pattern}:`;
  if (caseLine.length + 1 + quoted.length <= 100) {
    return [`${caseLine} ${quoted}`];
  }
  if (6 + quoted.length <= 100) return [caseLine, `      ${quoted}`];
  const lines = [];
  let line = "";
  for (const word of escaped.replaceAll('"""', '\\"""').split(" ")) {
    // Leaves room for the trailing " \".
    if (line && 6 + line.length + 1 + word.length + 2 > 100) {
      lines.push(`      ${line} \\`);
      line = word;
    } else {
      line = line ? `${line} ${word}` : word;
    }
  }
  return [caseLine, '      """', ...lines, `      ${line}`, '      """'];
}

function enumName(spec, prop) {
  return `MT${spec.name}${pascalCase(prop.names.ios)}`;
}

// Wraps text into /// lines that fit swift-format's 100 columns.
function docComment(text, indentation) {
  const prefix = `${" ".repeat(indentation)}/// `;
  const lines = [];
  let line = "";
  for (const word of text.split(/\s+/)) {
    if (line && prefix.length + line.length + 1 + word.length > 100) {
      lines.push(`${prefix}${line}`);
      line = word;
    } else {
      line = line ? `${line} ${word}` : word;
    }
  }
  if (line) lines.push(`${prefix}${line}`);
  return lines;
}
