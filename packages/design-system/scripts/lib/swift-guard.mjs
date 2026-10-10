import { readdir, readFile } from "node:fs/promises";
import { join, relative } from "node:path";
import { iosTextStyles } from "./resolve.mjs";
import { swiftReference, textRole } from "./swift.mjs";
import { formatNumber, hexString } from "./util.mjs";
import { orderedPaths } from "./web.mjs";

// Keeps hardcoded visual values out of the native app. Every font, color, opacity, spacing,
// size, radius, stroke, shadow, animation, and material in apps/ios/MemoTrail reads a generated
// token; literals live only in the generated tokens and the helpers that apply them. iOS is not
// built in CI, so this check reads the Swift sources and runs with pnpm design-system:check.

export const swiftSourceRoot = "apps/ios/MemoTrail";

// The only files where literal visual values may appear, relative to swiftSourceRoot.
export const tokenFiles = new Map([
  [
    "DesignSystem/Generated/DesignTokens.swift",
    "Generated from packages/design-system/tokens.",
  ],
  [
    "DesignSystem/Components/MTFoundations.swift",
    "Turns tokens into SwiftUI values: text roles, icon fonts, shadows, and line spacing.",
  ],
]);

// Deliberate exceptions. Each one names its file, its rule, and the exact source text it
// excuses (or, with no `match`, every finding of that rule in the file), and says why. An
// allowance that no longer matches anything fails the check, so this list stays current.
export const allowances = [
  {
    file: "DesignSystem/Components/MTRecordDetail.swift",
    rule: "system-color",
    match: ".background(Color.black)",
    reason:
      "An opaque mask that cuts the legend's gap out of the border with .destinationOut; it is never drawn.",
  },
  {
    file: "DesignSystem/Components/NativeRichTextEditor.swift",
    rule: "font",
    match: "UIFont.preferredFont(forTextStyle: .body",
    reason:
      "UITextView needs a UIFont; the editor sets the body text style, the same Dynamic Type style as MTFont.bodyLarge.",
  },
  {
    file: "DesignSystem/Components/NativeRichTextEditor.swift",
    rule: "system-color",
    match: "UIColor.label",
    reason:
      "UITextView typing attributes use the UIKit label color, as the system text view does.",
  },
  {
    file: "Models/EntryEmphasisContent.swift",
    rule: "system-color",
    match: "UIColor.label",
    reason:
      "Attributed text for UITextView uses the UIKit label color, as the system text view does.",
  },
  {
    file: "DesignSystem/Components/NativeRichTextEditor.swift",
    rule: "font",
    match: ".bold()",
    reason:
      "Bold is a writer's emphasis mark in rich text, not a design value.",
  },
  {
    file: "DesignSystem/Components/NativeRichTextEditor.swift",
    rule: "font",
    match: ".italic()",
    reason:
      "Italic is a writer's emphasis mark in rich text, not a design value.",
  },
  {
    file: "DesignSystem/Components/MTRichTextContent.swift",
    rule: "font",
    match: ".bold()",
    reason:
      "Bold is a writer's emphasis mark in rich text, not a design value.",
  },
  {
    file: "DesignSystem/Components/MTRichTextContent.swift",
    rule: "font",
    match: ".italic()",
    reason:
      "Italic is a writer's emphasis mark in rich text, not a design value.",
  },
  {
    file: "DesignSystem/Components/MTRichTextContent.swift",
    rule: "font",
    match: ".monospaced()",
    reason:
      "Code is a writer's mark in rich text; it keeps the surrounding role's size and switches only the design.",
  },
  {
    file: "DesignSystem/Components/NativeRichTextEditor.swift",
    rule: "font",
    match: "UIFont(",
    reason:
      "Rebuilds the run's font at the editor's Dynamic Type body size, keeping the writer's bold and italic traits.",
  },
  {
    file: "Models/EntryEmphasisContent.swift",
    rule: "font",
    match: "UIFont(descriptor:",
    reason:
      "Rebuilds the run's font from the editor's base font when the writer toggles bold or italic.",
  },
  {
    file: "DesignSystem/Components/MTOrganizationEditor.swift",
    rule: "shadow",
    match: ".shadow(",
    reason:
      "A Collection chip's glow uses MTColor.labelShade, which changes with the theme; MTShadow layers have one fixed color.",
  },
  {
    file: "DesignSystem/Components/MTToast.swift",
    rule: "animation",
    match: ".snappy(duration: MTMotion.",
    reason:
      "A system spring for toasts entering and leaving; its duration reads a motion token, and the tokens have no spring curve.",
  },
  {
    file: "Features/People/PersonEditorSheet.swift",
    rule: "animation",
    match: ".snappy(duration: MTMotion.",
    reason:
      "A system spring for the optional details disclosure; its duration reads a motion token, and the tokens have no spring curve.",
  },
  // Gradient stops and centers stay with the drawing they shape, as they do in the Web CSS
  // modules; the colors they blend are tokens.
  {
    file: "DesignSystem/Components/MTMedia.swift",
    rule: "gradient",
    reason:
      "The skeleton shimmer band, transcribed from the Web gradient in components/skeleton.module.css.",
  },
  {
    file: "Features/Authentication/AuthenticationView.swift",
    rule: "gradient",
    reason:
      "The warm glow near the top leading corner, transcribed from components/auth-gate.module.css.",
  },
  {
    file: "DesignSystem/Components/MTRecordDetail.swift",
    rule: "gradient",
    reason:
      "The accent glow on a record's fallback visual, transcribed from components/record-workspace.module.css.",
  },
  {
    file: "Features/Trash/TrashView.swift",
    rule: "gradient",
    reason:
      "The warm wash on a Trash item's visual, transcribed from components/trash-workspace.module.css.",
  },
  {
    file: "DesignSystem/Components/MTOrganizationEditor.swift",
    rule: "gradient",
    reason:
      "The sheen and shade bands that make a Collection chip read as a paper label.",
  },
  {
    file: "Features/Map/NativeLocationMap.swift",
    rule: "layout",
    match: "MKMapSize(width: 1, height: 1)",
    reason:
      "A one-map-point rectangle that adds a pin to the region the map fits; it is never drawn.",
  },
  {
    file: "DesignSystem/GalleryFoundations.swift",
    rule: "layout",
    reason:
      "Foundation specimens draw token values as bars, swatches, and sample grids at their own scale; the diagram chrome is not product UI.",
  },
  {
    file: "DesignSystem/GalleryFoundations.swift",
    rule: "opacity",
    match: "reduceMotion && moved ? 0.4 : 1",
    reason:
      "The reduced-motion specimen dims its dot to show that it changed state without moving.",
  },
];

const textStyles = Object.keys(iosTextStyles);
const textStylePattern = textStyles
  .slice()
  .sort((a, b) => b.length - a.length)
  .join("|");
const namedColors =
  "black|white|gray|grey|red|green|blue|orange|yellow|pink|purple|teal|indigo|mint|cyan|brown|primary|secondary|tertiary|quaternary|accentColor";
const uiKitColors =
  "label|secondaryLabel|tertiaryLabel|quaternaryLabel|systemBackground|secondarySystemBackground|tertiarySystemBackground|systemGroupedBackground|separator|opaqueSeparator|link|placeholderText|systemFill|tintColor|systemGray\\w*";
const easingCurves = {
  easeOut: "enter",
  easeIn: "exit",
  easeInOut: "inOut",
  linear: "linear",
};

const rules = {
  "legacy-typography": "MTTypography is retired; use an MTFont text role",
  font: "Literal font",
  tracking: "Literal letter spacing; use the tracked text role",
  color: "Literal color",
  "system-color": "System color used as a brand color or surface",
  opacity: "Literal opacity",
  layout: "Literal layout value",
  shadow: "Hand-written shadow; use mtShadow with an MTShadow token",
  animation: "Literal animation timing",
  material: "System material without its MTMaterial token",
  gradient: "Literal gradient geometry",
};

/** Replaces comments and the contents of string literals with spaces, keeping line breaks. */
export function codeOnly(source) {
  const out = source.split("");
  const blank = (from, to) => {
    for (let index = from; index < to; index += 1) {
      if (out[index] !== "\n") out[index] = " ";
    }
  };

  // Returns the index after the string that starts at `start` (at its first # or quote).
  const skipString = (start) => {
    let index = start;
    let hashes = 0;
    while (source[index] === "#") {
      hashes += 1;
      index += 1;
    }
    const quote = source.startsWith('"""', index) ? '"""' : '"';
    const closing = quote + "#".repeat(hashes);
    const escape = "\\" + "#".repeat(hashes);
    index += quote.length;
    // Blanks the literal text but keeps interpolated code, which can hold visual values too.
    let segmentStart = index;
    while (index < source.length && !source.startsWith(closing, index)) {
      if (source.startsWith(escape + "(", index)) {
        const codeStart = index + escape.length + 1;
        blank(segmentStart, codeStart);
        index = skipInterpolation(codeStart);
        blank(index - 1, index);
        segmentStart = index;
      } else if (source.startsWith(escape, index)) {
        index += escape.length + 1;
      } else {
        index += 1;
      }
    }
    blank(segmentStart, index);
    return Math.min(source.length, index + closing.length);
  };

  const skipInterpolation = (start) => {
    let depth = 1;
    let index = start;
    while (index < source.length && depth > 0) {
      const character = source[index];
      if (character === '"' || /^#+"/.test(source.slice(index, index + 8))) {
        index = skipString(index);
        continue;
      }
      if (character === "(") depth += 1;
      if (character === ")") depth -= 1;
      index += 1;
    }
    return index;
  };

  let index = 0;
  while (index < source.length) {
    if (source.startsWith("//", index)) {
      const end = source.indexOf("\n", index);
      const stop = end === -1 ? source.length : end;
      blank(index, stop);
      index = stop;
    } else if (source.startsWith("/*", index)) {
      let depth = 1;
      let end = index + 2;
      while (end < source.length && depth > 0) {
        if (source.startsWith("/*", end)) {
          depth += 1;
          end += 2;
        } else if (source.startsWith("*/", end)) {
          depth -= 1;
          end += 2;
        } else {
          end += 1;
        }
      }
      blank(index, end);
      index = end;
    } else if (
      source[index] === '"' ||
      /^#+"/.test(source.slice(index, index + 8))
    ) {
      index = skipString(index);
    } else {
      index += 1;
    }
  }
  return out.join("");
}

// The index of the parenthesis that closes the one at `open`, or the end of the code.
function closingParen(code, open) {
  let depth = 0;
  for (let index = open; index < code.length; index += 1) {
    if ("([{".includes(code[index])) depth += 1;
    if (")]}".includes(code[index])) {
      depth -= 1;
      if (depth === 0) return index;
    }
  }
  return code.length;
}

// The end of the line that holds `start`, or the end of the code on the last line.
function lineEnd(code, start) {
  const end = code.indexOf("\n", start);
  return end === -1 ? code.length : end;
}

// The end of a labeled argument's value: the next top-level comma or closing bracket.
function argumentEnd(code, start) {
  let depth = 0;
  for (let index = start; index < code.length; index += 1) {
    const character = code[index];
    if ("([{".includes(character)) depth += 1;
    if (")]}".includes(character)) {
      if (depth === 0) return index;
      depth -= 1;
    }
    if (character === "," && depth === 0) return index;
  }
  return code.length;
}

const numberPattern = /(?<![\w.])\d[\d_]*(?:\.\d[\d_]*)?(?![\w.])/g;

function numbers(text, offset) {
  return [...text.matchAll(numberPattern)].map((match) => ({
    value: Number(match[0].replaceAll("_", "")),
    index: offset + match.index,
  }));
}

/**
 * Finds hardcoded visual values in one Swift file. Each finding has its rule, its 1-based line,
 * the source line, and the literal value or construct it found.
 */
export function scanSwift(source) {
  const code = codeOnly(source);
  const lines = source.split("\n");
  const lineStarts = [0];
  for (let index = 0; index < source.length; index += 1) {
    if (source[index] === "\n") lineStarts.push(index + 1);
  }
  const lineOf = (index) => {
    let low = 0;
    let high = lineStarts.length - 1;
    while (low < high) {
      const middle = Math.ceil((low + high) / 2);
      if (lineStarts[middle] <= index) low = middle;
      else high = middle - 1;
    }
    return low + 1;
  };

  const findings = new Map();
  const add = (rule, index, detail = {}) => {
    const key = `${rule}:${index}`;
    if (findings.has(key)) return;
    const line = lineOf(index);
    findings.set(key, {
      rule,
      line,
      column: index - lineStarts[line - 1] + 1,
      text: lines[line - 1].trim(),
      ...detail,
    });
  };
  const each = (pattern, callback) => {
    for (const match of code.matchAll(pattern)) callback(match);
  };
  // Flags the numeric literals in code[start, end) that are not in `allowed`. A factor such as
  // the 2 in `2 * MTSpacing.s5` is arithmetic on a token, not a visual value.
  const literals = (rule, start, end, context, allowed = [0]) => {
    for (const { value, index } of numbers(code.slice(start, end), start)) {
      const before = code.slice(start, index);
      const after = code.slice(index, end).replace(/^[\d_.]+/, "");
      const isFactor = /[*/]\s*$/.test(before) || /^\s*\*/.test(after);
      if (!allowed.includes(value) && !isFactor)
        add(rule, index, { value, context });
    }
  };
  const callArguments = (match) => {
    const open = match.index + match[0].length - 1;
    return [open + 1, closingParen(code, open)];
  };

  // Typography
  each(/\bMTTypography\b/g, (match) => add("legacy-typography", match.index));
  each(/(?:\bFont)?\.system\(|\bFont\.custom\(/g, (match) => {
    add("font", match.index, { font: fontSpan(code, match.index) });
  });
  each(
    new RegExp(
      `\\bFont\\.(?:${textStylePattern})\\b|\\.font\\(\\s*\\.(?:${textStylePattern})\\b`,
      "g",
    ),
    (match) => add("font", match.index, { font: fontSpan(code, match.index) }),
  );
  each(/\.font\(/g, (match) => {
    const [start, end] = callArguments(match);
    const inner = code.slice(start, end);
    const style = new RegExp(`[?:]\\s*\\.(?:${textStylePattern})\\b`).exec(
      inner,
    );
    if (style) add("font", start + style.index, { font: inner });
  });
  each(
    /\.(?:weight|fontWeight|fontDesign|fontWidth)\(|\.(?:monospaced|bold|italic)\(\)/g,
    (match) => add("font", match.index, { font: fontSpan(code, match.index) }),
  );
  each(
    /\bUIFont\.(?:systemFont|boldSystemFont|italicSystemFont|monospacedSystemFont|monospacedDigitSystemFont|preferredFont)\(|\bUIFont\(/g,
    (match) => add("font", match.index),
  );
  each(/\.mtIcon\(/g, (match) => {
    const [start] = callArguments(match);
    literals("font", start, argumentEnd(code, start), "icon");
  });
  each(/\.(?:tracking|kerning)\(/g, (match) => {
    const [start, end] = callArguments(match);
    literals("tracking", start, end, "tracking");
  });

  // Colors
  each(
    /\b(?:Color|UIColor|CGColor)\(\s*(?:red|white|hue|displayP3Red|\.sRGB|\.displayP3|\.sRGBLinear|")|#colorLiteral/g,
    (match) =>
      add("color", match.index, { color: colorSpan(code, match.index) }),
  );
  each(
    new RegExp(
      `\\b(?:Color|UIColor)\\.(?:${namedColors}|${uiKitColors})\\b`,
      "g",
    ),
    (match) => add("system-color", match.index, { color: match[0] }),
  );
  each(
    new RegExp(
      `(?:foregroundStyle|foregroundColor|fill|stroke|strokeBorder|background|tint|border|overlay)\\(\\s*\\.(?:${namedColors})\\b|\\bcolor:\\s*\\.(?:${namedColors})\\b|[(,:?]\\s*\\.(?:black|white)\\.opacity\\(`,
      "g",
    ),
    (match) => add("system-color", match.index, { color: match[0] }),
  );

  // Opacity: 0 and 1 show and hide; any other value is a token.
  each(/\.opacity\(/g, (match) => {
    const [start, end] = callArguments(match);
    const receiver = /(MTColor\.\w+)\s*$/.exec(code.slice(0, match.index));
    literals("opacity", start, end, receiver?.[1] ?? "view", [0, 1]);
  });

  // Materials
  each(
    /\.(?:ultraThin|thin|regular|thick|ultraThick)Material\b|\b(?:background|fill)\(\s*\.bar\b/g,
    (match) => add("material", match.index, { material: match[0] }),
  );

  // Shadows
  each(/\.shadow\(|\bMTShadowLayer\(/g, (match) => add("shadow", match.index));

  // Animation
  each(
    /(?<!MTEasing)\.(?:easeIn|easeOut|easeInOut|linear|timingCurve)\b|\.(?:spring|snappy|smooth|bouncy|interactiveSpring|interpolatingSpring)\b/g,
    (match) => add("animation", match.index, { curve: match[0].slice(1) }),
  );
  each(/[(,]\s*duration:\s*/g, (match) => {
    const start = match.index + match[0].length;
    literals("animation", start, argumentEnd(code, start), "duration");
  });
  each(/\.(?:delay|speed)\(/g, (match) => {
    const [start, end] = callArguments(match);
    literals("animation", start, end, "delay");
  });

  // Layout
  const layoutCalls = [
    [/\.padding\(/g, "padding"],
    [/\.frame\(/g, "frame"],
    [/\.offset\(/g, "offset"],
    [/\.position\(/g, "offset"],
    [
      /\.(?:safeAreaPadding|contentMargins|lineSpacing|cornerRadius|blur)\(/g,
      "padding",
    ],
    [/\b(?:UIEdgeInsets|EdgeInsets|NSDirectionalEdgeInsets)\(/g, "padding"],
  ];
  for (const [pattern, context] of layoutCalls) {
    each(pattern, (match) => {
      const [start, end] = callArguments(match);
      literals("layout", start, end, context);
    });
  }
  each(/\.scaleEffect\(/g, (match) => {
    const [start, end] = callArguments(match);
    literals("layout", start, end, "scale", [0, 1]);
  });
  const labels = {
    spacing: "padding",
    lineSpacing: "padding",
    minLength: "padding",
    cornerRadius: "radius",
    lineWidth: "stroke",
    dash: "stroke",
    minimum: "frame",
    maximum: "frame",
    width: "frame",
    height: "frame",
    minimumHeight: "frame",
  };
  each(
    new RegExp(`[(,]\\s*(${Object.keys(labels).join("|")}):\\s*`, "g"),
    (match) => {
      const start = match.index + match[0].length;
      literals("layout", start, argumentEnd(code, start), labels[match[1]]);
    },
  );
  each(/\b(?:let|var)\s+\w+\s*:\s*CGFloat\s*=\s*/g, (match) => {
    const start = match.index + match[0].length;
    literals("layout", start, lineEnd(code, start), "frame");
  });
  each(/@ScaledMetric\b[^\n]*?\bvar\s+\w+(?:\s*:\s*\w+)?\s*=\s*/g, (match) => {
    const start = match.index + match[0].length;
    literals("layout", start, lineEnd(code, start), "frame", [0, 1]);
  });
  // A property named for a dimension that defaults to a number, such as
  // `var minimumHeight = 180.0`.
  each(
    /\b(?:let|var)\s+\w*(?:Height|Width|Spacing|Padding|Radius|Inset|Gap)\s*(?::\s*\w+)?\s*=\s*(?=-?\d[\d_.]*\s*$)/gm,
    (match) => {
      const start = match.index + match[0].length;
      literals("layout", start, lineEnd(code, start), "frame");
    },
  );
  // A computed CGFloat, such as a size enum's `var height: CGFloat { switch ... }`.
  each(/(?:\bvar\s+\w+\s*:\s*CGFloat|->\s*CGFloat)\s*\{/g, (match) => {
    const open = match.index + match[0].length - 1;
    literals("layout", open + 1, closingParen(code, open), "frame");
  });

  // Gradients: stop locations, unit points, and radii. 0 and 1 are the edges.
  each(/\bUnitPoint\(/g, (match) => {
    const [start, end] = callArguments(match);
    literals("gradient", start, end, "gradient", [0, 1]);
  });
  each(/[(,]\s*(?:location|startRadius|endRadius):\s*/g, (match) => {
    const start = match.index + match[0].length;
    literals("gradient", start, argumentEnd(code, start), "gradient", [0, 1]);
  });

  return [...findings.values()].sort(
    (a, b) => a.line - b.line || a.column - b.column,
  );
}

// The font expression around a match: the whole .font(...) argument when inside one.
function fontSpan(code, index) {
  const lineStart = code.lastIndexOf("\n", index) + 1;
  const open = code.lastIndexOf(".font(", index);
  if (open !== -1 && closingParen(code, open + 5) > index) {
    return code.slice(open + 6, closingParen(code, open + 5));
  }
  const lineEnd = code.indexOf("\n", index);
  return code.slice(lineStart, lineEnd === -1 ? code.length : lineEnd);
}

function colorSpan(code, index) {
  const open = code.indexOf("(", index);
  let end = closingParen(code, open) + 1;
  const opacity = /^\s*\.opacity\(([\d.]+)\)/.exec(code.slice(end));
  if (opacity) end += opacity[0].length;
  return code.slice(index, end);
}

/** Indexes the generated iOS tokens by value so each finding can name its replacement. */
export function tokenIndex(system) {
  const light = system.platforms.ios.light;
  const dark = system.platforms.ios.dark;
  const index = {
    dimensions: [],
    numbers: [],
    durations: [],
    colors: [],
    roles: [],
    shadows: [],
    materials: [],
  };
  for (const path of orderedPaths(light)) {
    const token = light.get(path);
    const reference = swiftReference(path);
    if (!reference) continue;
    const group = path.split(".")[0];
    if (token.type === "dimension") {
      index.dimensions.push({ path, group, reference, value: token.value });
    } else if (token.type === "number" && group !== "lineHeight") {
      index.numbers.push({ path, reference, value: token.value });
    } else if (token.type === "duration") {
      index.durations.push({ reference, value: token.value / 1000 });
    } else if (token.type === "color" && group === "color") {
      const other = dark.get(path).value;
      index.colors.push({
        reference,
        light: hexString(token.value.channels),
        dark: hexString(other.channels),
        lightAlpha: token.value.alpha,
        darkAlpha: other.alpha,
        mix: token.extension.mix,
      });
    } else if (token.type === "typography") {
      const role = textRole(token);
      index.roles.push({
        ...role,
        reference: role.font
          ? `MTFont.${role.name}`
          : `mtTextRole(.${role.name})`,
      });
    } else if (token.type === "shadow" && group === "shadow") {
      index.shadows.push({ reference, layers: token.value });
    }
  }
  for (const name of new Set(
    [...light.keys()]
      .filter((path) => path.startsWith("material."))
      .map((path) => path.split(".")[1]),
  )) {
    const material = system.groups.get(`material.${name}`)?.ios?.material;
    if (material)
      index.materials.push({ reference: `MTMaterial.${name}`, material });
  }
  return index;
}

const preferredGroups = {
  padding: ["space", "layout", "size", "radius"],
  offset: ["space", "layout", "size"],
  frame: ["size", "layout", "space"],
  radius: ["radius", "layout"],
  stroke: ["size", "state", "layout"],
  icon: ["size"],
};

/** The tokens that reproduce a finding's value, best match first. */
export function suggest(finding, index) {
  const unique = (items) => [...new Set(items)];
  switch (finding.rule) {
    case "legacy-typography":
      return ["an MTFont text role"];
    case "layout": {
      if (finding.context === "scale") {
        return index.numbers
          .filter((token) => token.value === finding.value)
          .map((token) => token.reference);
      }
      const groups = preferredGroups[finding.context];
      // Icon sizes size glyphs, and strokes size lines; neither is a gap or a frame.
      const fits = (token) =>
        !token.path.startsWith("size.icon.") &&
        (finding.context === "stroke" ||
          !token.path.startsWith("size.stroke."));
      return unique(
        index.dimensions
          .filter(
            (token) =>
              token.value === finding.value &&
              groups.includes(token.group) &&
              fits(token),
          )
          .sort((a, b) => groups.indexOf(a.group) - groups.indexOf(b.group))
          .map((token) => token.reference),
      );
    }
    case "font": {
      if (finding.context === "icon") {
        return index.dimensions
          .filter(
            (token) =>
              token.path.startsWith("size.icon.") &&
              token.value === finding.value,
          )
          .map((token) => token.reference);
      }
      return fontSuggestions(finding, index);
    }
    case "tracking":
      return index.roles
        .filter((role) => role.tracking === finding.value)
        .map((role) => `mtTextRole(.${role.name})`);
    case "opacity": {
      if (finding.context === "view") {
        return index.numbers
          .filter((token) => token.value === finding.value)
          .map((token) => token.reference);
      }
      const base = index.colors.find(
        (color) => color.reference === finding.context,
      );
      return index.colors
        .filter(
          (color) =>
            base &&
            color.light === base.light &&
            color.dark === base.dark &&
            color.lightAlpha === finding.value &&
            color.darkAlpha === finding.value,
        )
        .map((color) => color.reference);
    }
    case "color":
    case "system-color":
      return colorSuggestions(finding, index);
    case "animation": {
      if (finding.curve) {
        const curve = easingCurves[finding.curve];
        return curve ? [`MTEasing.${curve}.animation(duration:)`] : [];
      }
      return index.durations
        .filter((token) => Math.abs(token.value - finding.value) < 1e-9)
        .map((token) => token.reference);
    }
    case "shadow":
      return ["mtShadow(MTShadow.<name>)"];
    case "material": {
      const name = /\.(\w+)Material/.exec(finding.material)?.[1] ?? "bar";
      return index.materials
        .filter((material) => material.material === name)
        .map((material) => material.reference);
    }
    default:
      return [];
  }
}

function fontSuggestions(finding, index) {
  const span = finding.font ?? finding.text;
  const style = new RegExp(`\\.(${textStylePattern})\\b`).exec(span)?.[1];
  const base = /MTFont\.(\w+)/.exec(span)?.[1];
  const baseRole = index.roles.find((role) => role.name === base);
  const textStyle = style ?? baseRole?.textStyle ?? null;
  const size = Number(/size:\s*([\d.]+)/.exec(span)?.[1]) || null;
  const weights = [...span.matchAll(/(?:weight:\s*|\.weight\()\.(\w+)/g)];
  const design =
    /design:\s*\.(\w+)/.exec(span)?.[1] ??
    (/\.monospaced\(\)/.test(span) ? "monospaced" : null);
  const weight =
    weights.at(-1)?.[1] ??
    (textStyle && !size
      ? iosTextStyles[textStyle].weight === 600
        ? "semibold"
        : "regular"
      : (baseRole?.weight ?? "regular"));
  const candidates = index.roles.filter((role) => {
    if (role.weight !== weight) return false;
    if (role.design !== (design ?? baseRole?.design ?? "default")) return false;
    if (size) return role.size === size && !role.textStyle;
    return (
      textStyle &&
      role.textStyle === textStyle &&
      role.size === iosTextStyles[textStyle].size
    );
  });
  const roles = candidates.map((role) => role.reference);
  if (size && /Image\(|Label\(/.test(finding.text)) {
    roles.push(`.mtIcon(MTSize.Icon.s${formatNumber(size)})`);
  }
  return roles;
}

function colorSuggestions(finding, index) {
  const text = finding.color ?? finding.text;
  let hex = null;
  let alpha = Number(/\.opacity\(([\d.]+)\)/.exec(text)?.[1] ?? 1);
  const rgb =
    /red:\s*(\d+)\s*\/\s*255[^,]*,\s*green:\s*(\d+)\s*\/\s*255[^,]*,\s*blue:\s*(\d+)\s*\/\s*255/.exec(
      text,
    );
  if (rgb) hex = hexString(rgb.slice(1, 4).map(Number));
  else if (/\bwhite\b/.test(text)) hex = "#FFFFFF";
  else if (/\bblack\b/.test(text)) hex = "#000000";
  if (!hex) return [];
  return index.colors
    .filter(
      (color) =>
        color.light === hex &&
        color.dark === hex &&
        color.lightAlpha === alpha &&
        color.darkAlpha === alpha,
    )
    .map((color) => color.reference);
}

async function swiftFiles(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = await Promise.all(
    entries.map((entry) => {
      const path = join(directory, entry.name);
      if (entry.isDirectory()) return swiftFiles(path);
      return entry.name.endsWith(".swift") ? [path] : [];
    }),
  );
  return files.flat().sort();
}

/**
 * Scans every Swift file under swiftSourceRoot. Returns the findings no allowance excuses, each
 * with its suggested tokens, and the allowances that matched nothing.
 */
export async function checkSwiftSources({
  root,
  system,
  allowed = allowances,
}) {
  const directory = join(root, swiftSourceRoot);
  const index = tokenIndex(system);
  const used = new Set();
  const failures = [];

  for (const path of await swiftFiles(directory)) {
    const file = relative(directory, path);
    if (tokenFiles.has(file)) continue;
    for (const finding of scanSwift(await readFile(path, "utf8"))) {
      const allowance = allowed.find(
        (entry) =>
          entry.file === file &&
          entry.rule === finding.rule &&
          (entry.match === undefined || finding.text.includes(entry.match)),
      );
      if (allowance) {
        used.add(allowance);
        continue;
      }
      failures.push({
        ...finding,
        file: join(swiftSourceRoot, file),
        message: rules[finding.rule],
        suggestions: suggest(finding, index),
      });
    }
  }

  return { failures, stale: allowed.filter((entry) => !used.has(entry)) };
}

/** One failure as `file:line:column: message. Use X.` for the terminal. */
export function formatFailure(failure) {
  const value =
    failure.value === undefined ? "" : ` ${formatNumber(failure.value)}`;
  const use =
    failure.suggestions.length > 0
      ? ` Use ${failure.suggestions.join(" or ")}.`
      : " No token has this value yet; add one to packages/design-system/tokens.";
  return `${failure.file}:${failure.line}:${failure.column}: ${failure.message}${value}.${use}\n    ${failure.text}`;
}
