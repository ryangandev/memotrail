import { isPublic, themes } from "../lib/resolve.mjs";
import {
  cssName,
  cssValue,
  makeCss,
  relativeValue,
  textCase,
  webTokens,
} from "../lib/web.mjs";
import { aliasPath, formatNumber, hexString } from "../lib/util.mjs";

// Writes tokens.json for the Claude Design copy, and the CSS variables it cannot express.
//
// Every token is named exactly like its Web CSS variable without the leading --, so the copy's
// compiled tokens.css and the bundled component CSS share one namespace. Colors and shadows carry
// a light and a dark value; every other family is the same in both themes.

export const tokenNamePattern = /^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$/;
export const coreFamilies = ["color", "spacing", "radius", "shadow"];
export const maximumExtraFamilies = 12;
export const maximumExtraTokens = 60;

// Each Web token lands in the first family whose test matches. A token no rule matches stops the
// export, so a new group needs a decision here. Font stacks become type.families, and text roles
// become type groups.
const familyRules = [
  ["color", (path, type) => type === "color"],
  ["shadow", (path, type) => type === "shadow"],
  [
    "spacing",
    (path) => path.startsWith("space.") || path.startsWith("textSpace."),
  ],
  ["radius", (path) => path.startsWith("radius.")],
  ["fontSize", (path) => path.startsWith("font.size.")],
  ["fontWeight", (path) => path.startsWith("font.weight.")],
  ["lineHeight", (path) => path.startsWith("lineHeight.")],
  // One component's geometry, such as size.recordCard.visualHeight, stays apart from the shared
  // scale so neither family outgrows the copy's limit as more components are specified.
  [
    "componentSize",
    (path) =>
      path.startsWith("size.") && !sharedSizes.includes(path.split(".")[1]),
  ],
  [
    "size",
    (path, type) =>
      path.startsWith("size.") ||
      (path.startsWith("state.focus.") && type === "dimension"),
  ],
  [
    "layout",
    (path) =>
      path.startsWith("layout.pageWidth.") ||
      path.startsWith("layout.pageGutter.") ||
      path.startsWith("layout.inset."),
  ],
  [
    "breakpoint",
    (path) =>
      path.startsWith("layout.breakpoint.") ||
      path.startsWith("layout.container."),
  ],
  ["zIndex", (path) => path.startsWith("layout.layer.")],
  [
    "opacity",
    (path) =>
      path.startsWith("state.disabled.opacity.") ||
      path.startsWith("state.muted.opacity."),
  ],
  ["duration", (path, type) => type === "duration"],
  ["easing", (path, type) => type === "cubicBezier"],
  [
    "material",
    (path, type) =>
      path.startsWith("material.") && ["dimension", "number"].includes(type),
  ],
];

// The size groups every component draws from; any other size group belongs to one component.
const sharedSizes = ["control", "field", "hitTarget", "icon", "stroke"];

const typeGroupNames = { serif: "Serif", sans: "Sans", mono: "Mono" };

export function tokenName(path) {
  return cssName(path).slice(2);
}

export function makeTokens({ system, icons, contrast, meta, title }) {
  const web = webTokens(system);
  const families = Object.fromEntries(
    familyRules.map(([family]) => [family, []]),
  );
  const fontFamilies = {};
  const textRoles = [];
  const grounds = textGrounds(contrast);

  for (const path of web.paths) {
    const light = web.light.get(path);
    if (light.type === "fontFamily") {
      fontFamilies[path.split(".").at(-1)] = cssValue(light);
      continue;
    }
    if (light.type === "typography") {
      textRoles.push(path);
      continue;
    }
    const family = familyRules.find(([, test]) => test(path, light.type))?.[0];
    if (!family) {
      throw new Error(
        `{${path}} has no Claude Design token family. Add a rule to familyRules in scripts/claude-design/tokens.mjs.`,
      );
    }
    families[family].push({
      name: tokenName(path),
      value: tokenValue(path, family, web),
      usage: tokenUsage(path, { system, web, grounds }),
    });
  }

  const names = Object.values(families)
    .flat()
    .map((token) => token.name);
  for (const name of names) {
    if (!tokenNamePattern.test(name)) {
      throw new Error(`Token name ${name} does not fit the copy's pattern.`);
    }
  }
  const duplicate = names.find((name, index) => names.indexOf(name) !== index);
  if (duplicate) throw new Error(`Two tokens are named ${duplicate}.`);

  const extras = Object.keys(families).filter(
    (family) => !coreFamilies.includes(family) && families[family].length > 0,
  );
  if (extras.length > maximumExtraFamilies) {
    throw new Error(
      `The copy accepts at most ${maximumExtraFamilies} extra families, got ${extras.length}.`,
    );
  }
  for (const family of extras) {
    if (families[family].length > maximumExtraTokens) {
      throw new Error(
        `The ${family} family has ${families[family].length} tokens; the copy accepts at most ${maximumExtraTokens}.`,
      );
    }
  }

  const tokens = {
    name: title,
    version: 1,
    meta,
    color: {
      themes: themes.map((id) => ({
        id,
        name: id[0].toUpperCase() + id.slice(1),
      })),
      tokens: families.color,
    },
    type: {
      fonts: [],
      families: fontFamilies,
      groups: typeGroups(textRoles, { system, web, fontFamilies }),
    },
    spacing: { tokens: families.spacing },
    radius: { tokens: families.radius },
    shadow: { tokens: families.shadow },
  };
  for (const family of extras) tokens[family] = { tokens: families[family] };

  return {
    tokens,
    stylesheet: unexpressedVariables(system, new Set(names), icons),
  };
}

// Values

function tokenValue(path, family, web) {
  const values = themes.map((theme) =>
    family === "color"
      ? colorValue(web[theme].get(path), web[theme])
      : (relativeValue(web[theme].get(path)) ??
        plainValue(web[theme].get(path))),
  );
  if (family === "color") {
    return Object.fromEntries(
      themes.map((theme, index) => [theme, values[index]]),
    );
  }
  if (family === "shadow") {
    return values.every((value) => value === values[0])
      ? values[0]
      : Object.fromEntries(
          themes.map((theme, index) => [theme, values[index]]),
        );
  }
  if (values.some((value) => value !== values[0])) {
    throw new Error(
      `{${path}} differs by theme, but the ${family} family has one value.`,
    );
  }
  return values[0];
}

// A color that aliases another exported color stays an alias, like the var() it is on Web.
// Everything else, including mixed and translucent colors, is written as its exact value.
function colorValue(token, tokens) {
  if (token.alias && isPublic(token.alias)) {
    const target = tokens.get(token.alias);
    if (target?.type === "color") return `{${tokenName(token.alias)}}`;
  }
  return colorString(token.value);
}

export function colorString({ channels, alpha }) {
  return alpha === 1
    ? hexString(channels)
    : `rgba(${channels.join(", ")}, ${formatNumber(alpha)})`;
}

function plainValue({ type, value }) {
  switch (type) {
    case "dimension":
      return `${formatNumber(value)}px`;
    case "duration":
      return `${formatNumber(value)}ms`;
    case "cubicBezier":
      return `cubic-bezier(${value.map(formatNumber).join(", ")})`;
    case "number":
    case "fontWeight":
      return value;
    case "shadow":
      return value
        .map((layer) =>
          [
            layer.inset ? "inset" : null,
            pixels(layer.x),
            pixels(layer.y),
            pixels(layer.blur),
            layer.spread === 0 ? null : pixels(layer.spread),
            colorString(layer),
          ]
            .filter(Boolean)
            .join(" "),
        )
        .join(", ");
    default:
      throw new Error(`The copy has no value form for ${type} tokens.`);
  }
}

function pixels(value) {
  return value === 0 ? "0" : `${formatNumber(value)}px`;
}

// Usage

function tokenUsage(path, { system, web, grounds }) {
  const token = web.light.get(path);
  const parts = [describe(path, token, system)];

  const mix = token.extension.mix;
  if (mix && !token.overridden) parts.push(mixNote(mix, web.light));

  if (token.alias && isPublic(token.alias) && token.type !== "color") {
    parts.push(`Same value as ${tokenName(token.alias)}.`);
  }

  const ground = grounds.get(path);
  if (ground) parts.push(...ground);

  if (token.platforms.length === 1)
    parts.push(`${platformName(token.platforms[0])} only.`);
  const iosMaterial = materialOf(path, system);
  if (iosMaterial) {
    parts.push(`On iOS the surface is the system ${iosMaterial} material.`);
  }
  const ios = iosValue(path, token, system);
  if (ios) parts.push(`On iOS it is ${ios}.`);

  return parts.join(" ");
}

// A token's own $description, or else its nearest group's, so every token says where it is used.
export function describe(path, token, system) {
  if (token.description) return sentence(token.description);
  const segments = path.split(".");
  for (let length = segments.length - 1; length > 0; length -= 1) {
    const description = system.groupDescriptions.get(
      segments.slice(0, length).join("."),
    );
    if (description) return sentence(description);
  }
  throw new Error(
    `{${path}} has no $description and no group description. Describe where it is used in packages/design-system/tokens.`,
  );
}

function sentence(text) {
  const trimmed = text.trim();
  return /[.!?]$/.test(trimmed) ? trimmed : `${trimmed}.`;
}

function mixNote({ colors, weight }, tokens) {
  const operand = (reference) => {
    const path = aliasPath(reference);
    return isPublic(path)
      ? tokenName(path)
      : colorString(tokens.get(path).value);
  };
  const percent = (value) => `${formatNumber(value * 100)}%`;
  return colors.length === 1
    ? `Mixes ${percent(weight)} ${operand(colors[0])} with transparent; Web writes it as that color-mix().`
    : `Mixes ${percent(weight)} ${operand(colors[0])} with ${percent(1 - weight)} ${operand(colors[1])}; Web writes it as that color-mix().`;
}

function platformName(platform) {
  return platform === "web" ? "Web" : "iOS";
}

function materialOf(path, system) {
  const [group, name] = path.split(".");
  if (group !== "material") return null;
  return system.groups.get(`material.${name}`)?.ios?.material ?? null;
}

function iosValue(path, token, system) {
  const ios = system.platforms.ios.light.get(path);
  if (!ios || !token.platforms.includes("ios")) return null;
  if (token.type === "color") {
    const differs = themes.some((theme) => {
      const web = system.platforms.web[theme].get(path).value;
      const native = system.platforms.ios[theme].get(path).value;
      return colorString(web) !== colorString(native);
    });
    if (!differs) return null;
    return themes
      .map(
        (theme) =>
          `${colorString(system.platforms.ios[theme].get(path).value)} in ${theme}`,
      )
      .join(" and ");
  }
  const web = plainValue(token);
  const native = plainValue(ios);
  return web === native ? null : String(native);
}

// For each color read as text, the grounds contrast.json checks it on, and its named exceptions.
function textGrounds(contrast) {
  const grounds = new Map();
  const stack = (layers) => layers.map(tokenName).join(" over ");
  for (const check of contrast.checks) {
    const notes = grounds.get(check.text) ?? [];
    notes.push(
      `As text at ${tokenName(check.role)} size or larger, it reads on ${check.on.map(stack).join(", ")}; contrast.json holds these to WCAG AA in both themes.`,
    );
    grounds.set(check.text, notes);
  }
  for (const exception of contrast.exceptions) {
    const notes = grounds.get(exception.text) ?? [];
    notes.push(
      `Contrast exception "${exception.name}" (${exception.themes.join(" and ")}) on ${exception.on.map(stack).join(", ")}: ${exception.reason}`,
    );
    grounds.set(exception.text, notes);
  }
  return grounds;
}

// Type

function typeGroups(paths, { system, web, fontFamilies }) {
  const groups = new Map();
  for (const path of paths) {
    const token = web.light.get(path);
    const family = fontFamilyKey(token, fontFamilies);
    const styles = groups.get(family) ?? [];
    styles.push(typeStyle(path, token, system));
    groups.set(family, styles);
  }
  return [...groups].map(([family, styles]) => ({
    name: typeGroupNames[family] ?? family,
    family,
    styles,
  }));
}

function fontFamilyKey(token, fontFamilies) {
  const alias = token.value.aliases.fontFamily;
  if (alias?.startsWith("font.family.")) return alias.split(".").at(-1);
  const stack = cssValue({ type: "fontFamily", value: token.value.fontFamily });
  const key = Object.keys(fontFamilies).find(
    (name) => fontFamilies[name] === stack,
  );
  if (!key) {
    throw new Error(
      `{${token.path}} uses a font stack that font.family lacks.`,
    );
  }
  return key;
}

function typeStyle(path, token, system) {
  const { value } = token;
  const style = {
    name: tokenName(path),
    fontSize: `${formatNumber(value.fontSize)}px`,
    lineHeight: value.lineHeight,
    fontWeight: value.fontWeight,
  };
  if (value.letterSpacing !== 0) {
    style.letterSpacing = `${formatNumber(Number((value.letterSpacing / value.fontSize).toFixed(4)))}em`;
  }

  const notes = [describe(path, token, system)];
  if (textCase(token) !== "none") notes.push(`Set in ${textCase(token)}.`);
  const fluid = token.extension.web?.fluid;
  if (fluid) {
    notes.push(
      `On Web the size is fluid: clamp(${formatNumber(fluid.minimum.value)}px, ${formatNumber(fluid.viewportWidth)}vw, ${formatNumber(value.fontSize)}px).`,
    );
  }
  const ios = system.platforms.ios.light.get(path);
  if (ios) {
    const textStyle = ios.extension.ios?.textStyle;
    notes.push(
      textStyle === "none"
        ? `On iOS it is a fixed ${formatNumber(ios.value.fontSize)}pt.`
        : `On iOS it is ${formatNumber(ios.value.fontSize)}pt and scales with the ${textStyle} Dynamic Type style.`,
    );
  } else {
    notes.push("Web only.");
  }
  style.usage = notes.join(" ");
  return style;
}

// CSS the copy cannot express

// The generated Web CSS declares one variable per line. Variables tokens.json already declares
// are left to the copy's compiled tokens.css; the rest, such as text role properties, font
// stacks, material backdrop filters, and icon images, go into a :root block at the top of bundle.css.
export function unexpressedVariables(system, declared, icons) {
  const blocks = cssBlocks(
    makeCss(system, "packages/design-system/tokens", icons),
  );
  const light = new Map([...blocks.shared, ...blocks.light]);
  const rootLines = [];
  const darkLines = [];
  for (const [name, value] of light) {
    if (declared.has(name.slice(2))) continue;
    rootLines.push(`  ${name}: ${value};`);
    const dark = blocks.dark.get(name);
    if (dark !== undefined && dark !== value)
      darkLines.push(`  ${name}: ${dark};`);
  }
  for (const name of blocks.dark.keys()) {
    if (!light.has(name)) throw new Error(`${name} is declared only in dark.`);
  }

  return [
    ":root {",
    ...rootLines,
    "}",
    "",
    ':root,\n[data-theme="light"] {\n  color-scheme: light;\n}',
    "",
    '[data-theme="dark"] {',
    "  color-scheme: dark;",
    ...darkLines,
    "}",
    "",
  ].join("\n");
}

function cssBlocks(css) {
  const blocks = { shared: new Map(), light: new Map(), dark: new Map() };
  let current = null;
  let selector = "";
  for (const line of css.split("\n")) {
    const trimmed = line.trim();
    if (trimmed.endsWith("{")) {
      selector = `${selector} ${trimmed}`.trim();
      if (selector === ":root {") current = blocks.shared;
      else if (selector === ':root, [data-theme="light"] {')
        current = blocks.light;
      else if (selector === '[data-theme="dark"] {') current = blocks.dark;
      else current = null;
      continue;
    }
    if (trimmed.endsWith(",")) {
      selector = `${selector} ${trimmed}`.trim();
      continue;
    }
    if (trimmed === "}") {
      selector = "";
      current = null;
      continue;
    }
    const match = trimmed.match(/^(--[\w-]+):\s*(.+);$/);
    if (match && current) current.set(match[1], match[2]);
  }
  for (const [name, map] of Object.entries(blocks)) {
    if (map.size === 0)
      throw new Error(`The generated CSS has no ${name} block.`);
  }
  return blocks;
}
