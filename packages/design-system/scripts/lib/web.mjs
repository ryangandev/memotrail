import { isPublic, themes } from "./resolve.mjs";
import {
  deepEqual,
  formatNumber,
  hexString,
  indent,
  kebabCase,
  pascalCase,
  setPath,
} from "./util.mjs";

// Writes the Web outputs: CSS custom properties, the gallery catalog, and typed TypeScript data.

// Top-level groups in output order. Adding a group means choosing its place here.
export const groupOrder = [
  "color",
  "font",
  "lineHeight",
  "type",
  "space",
  "size",
  "radius",
  "layout",
  "motion",
  "shadow",
  "state",
  "material",
  "elevation",
];

const typographyProperties = [
  ["fontFamily", "font-family"],
  ["fontSize", "font-size"],
  ["fontWeight", "font-weight"],
  ["lineHeight", "line-height"],
  ["letterSpacing", "letter-spacing"],
  ["textCase", "text-transform"],
];

export function webTokens(system) {
  const light = system.platforms.web.light;
  const dark = system.platforms.web.dark;
  const paths = orderedPaths(light);
  const themed = new Set(
    paths.filter(
      (path) =>
        !deepEqual(light.get(path).value, dark.get(path).value) ||
        light.get(path).alias !== dark.get(path).alias,
    ),
  );
  return { light, dark, paths, themed };
}

export function orderedPaths(tokens) {
  const paths = [...tokens.keys()].filter(isPublic);
  for (const path of paths) {
    if (!groupOrder.includes(path.split(".")[0])) {
      throw new Error(
        `{${path}} is in a group the generator does not know. Add "${path.split(".")[0]}" to groupOrder.`,
      );
    }
  }
  const rank = (path) => groupOrder.indexOf(path.split(".")[0]);
  return paths
    .map((path, index) => ({ path, index }))
    .sort((a, b) => rank(a.path) - rank(b.path) || a.index - b.index)
    .map(({ path }) => path);
}

// CSS

export function makeCss(system, sourceLabel) {
  const web = webTokens(system);
  const shared = [];
  const light = [];
  const dark = [];
  const derived = materialFilters(web);

  for (const path of web.paths) {
    if (web.themed.has(path)) {
      light.push(...cssDeclarations(web.light.get(path), web.light));
      dark.push(...cssDeclarations(web.dark.get(path), web.dark));
    } else {
      shared.push(...cssDeclarations(web.light.get(path), web.light));
      if (derived.has(path)) shared.push(derived.get(path));
    }
  }

  const names = [...shared, ...light].map((line) => line.split(":")[0]);
  const duplicate = names.find((name, index) => names.indexOf(name) !== index);
  if (duplicate) {
    throw new Error(`Two tokens generate the CSS variable ${duplicate}.`);
  }

  return `/* Generated from ${sourceLabel}. Do not edit directly. */

:root {
${indent(shared)}
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

export function cssName(path, property) {
  const name = path.split(".").map(kebabCase).join("-");
  return `--mt-${name}${property ? `-${property}` : ""}`;
}

function cssDeclarations(token, tokens) {
  if (token.type === "typography") {
    return typographyProperties.map(
      ([property, cssProperty]) =>
        `${cssName(token.path, cssProperty)}: ${typographyValue(token, property, tokens)};`,
    );
  }
  return [`${cssName(token.path)}: ${cssReferenceOrValue(token, tokens)};`];
}

function cssReferenceOrValue(token, tokens) {
  if (token.alias && isPublic(token.alias) && tokens.has(token.alias)) {
    return `var(${cssName(token.alias)})`;
  }
  if (token.type === "color" && token.extension.mix && !token.overridden) {
    return cssMix(token, tokens);
  }
  return cssValue(token);
}

// A mixed color stays a color-mix() of its sources. Chrome keeps full precision for the
// result and blends gradients through it in Oklab, so this draws exactly what the CSS it
// replaces drew; a rounded rgb() or hex value can be one level off.
function cssMix(token, tokens) {
  const { colors, weight } = token.extension.mix;
  const operand = (reference) => {
    const path = reference.slice(1, -1);
    const source = tokens.get(path);
    if (!source) {
      throw new Error(`{${token.path}} mixes ${reference}, which Web lacks.`);
    }
    return isPublic(path) ? `var(${cssName(path)})` : cssColor(source.value);
  };
  const second = colors[1] ? operand(colors[1]) : "transparent";
  return `color-mix(in srgb, ${operand(colors[0])} ${formatNumber(Number((weight * 100).toFixed(4)))}%, ${second})`;
}

function typographyValue(token, property, tokens) {
  const value = token.value;
  if (property === "textCase") return textCase(token);
  if (property === "letterSpacing") {
    return value.letterSpacing === 0
      ? "0"
      : `${formatNumber(Number((value.letterSpacing / value.fontSize).toFixed(4)))}em`;
  }
  if (property === "fontSize" && token.extension.web?.fluid) {
    const { minimum, viewportWidth } = token.extension.web.fluid;
    if (minimum.unit !== "px" || !(minimum.value < value.fontSize)) {
      throw new Error(
        `{${token.path}} fluid minimum must be a px size below the font size.`,
      );
    }
    return `clamp(${minimum.value}px, ${formatNumber(viewportWidth)}vw, ${value.fontSize}px)`;
  }

  const alias = value.aliases[property];
  if (alias && isPublic(alias) && tokens.has(alias)) {
    return `var(${cssName(alias)})`;
  }
  switch (property) {
    case "fontFamily":
      return value.fontFamily.map(cssFontFamily).join(", ");
    case "fontSize":
      return `${value.fontSize}px`;
    default:
      return String(value[property]);
  }
}

export function textCase(token) {
  return token.extension.textCase ?? "none";
}

export function cssValue({ type, value }) {
  switch (type) {
    case "color":
      return cssColor(value);
    case "dimension":
      return `${value}px`;
    case "duration":
      return `${value}ms`;
    case "fontFamily":
      return value.map(cssFontFamily).join(", ");
    case "cubicBezier":
      return `cubic-bezier(${value.map(formatNumber).join(", ")})`;
    case "shadow":
      return value
        .map((layer) =>
          [
            layer.inset ? "inset" : null,
            cssLength(layer.x),
            cssLength(layer.y),
            cssLength(layer.blur),
            layer.spread === 0 ? null : cssLength(layer.spread),
            cssColor(layer),
          ]
            .filter(Boolean)
            .join(" "),
        )
        .join(", ");
    default:
      return String(value);
  }
}

export function cssColor({ channels, alpha }) {
  return alpha === 1
    ? hexString(channels)
    : `rgb(${channels.join(" ")} / ${formatNumber(alpha)})`;
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

// Each material with a blur also gets a ready backdrop-filter value, emitted after its parts.
function materialFilters(web) {
  const filters = new Map();
  const groups = new Map();
  for (const path of web.paths) {
    const [group, name, part] = path.split(".");
    if (group !== "material" || !["blur", "saturation"].includes(part))
      continue;
    if (web.themed.has(path)) {
      throw new Error(`{${path}} must be the same in every theme.`);
    }
    groups.set(name, { ...groups.get(name), [part]: path });
  }
  for (const [name, parts] of groups) {
    if (!parts.blur) {
      throw new Error(`{material.${name}} has a saturation but no blur.`);
    }
    const blur = web.light.get(parts.blur);
    const saturation = parts.saturation && web.light.get(parts.saturation);
    if (
      blur.type !== "dimension" ||
      (saturation && saturation.type !== "number")
    ) {
      throw new Error(
        `{material.${name}} blur must be a dimension and saturation a number.`,
      );
    }
    const value = [
      `blur(${blur.value}px)`,
      saturation ? `saturate(${formatNumber(saturation.value * 100)}%)` : null,
    ]
      .filter(Boolean)
      .join(" ");
    const last = parts.saturation ?? parts.blur;
    filters.set(
      last,
      `${cssName(`material.${name}`, "backdrop-filter")}: ${value};`,
    );
  }
  return filters;
}

// Catalog

// The development gallery lists every public Web token with its resolved value. A group whose
// values differ by theme appears once per theme.
export function makeCatalog(system, icons) {
  const web = webTokens(system);
  const catalog = { name: system.name };
  const themedGroups = new Set(
    [...web.themed].map((path) => path.split(".")[0]),
  );
  const descriptions = {};

  for (const path of web.paths) {
    const [group, ...rest] = path.split(".");
    if (themedGroups.has(group)) {
      for (const theme of themes) {
        setPath(
          catalog,
          [group, theme, ...rest],
          catalogValue(web[theme].get(path)),
        );
      }
    } else {
      setPath(catalog, path.split("."), catalogValue(web.light.get(path)));
    }
    const description = web.light.get(path).description;
    if (description) descriptions[path] = description;
  }

  catalog.icon = Object.fromEntries(
    icons.icons.map((icon) => [
      icon.name,
      {
        description: icon.description,
        platforms: icon.platforms,
        sfSymbol: icon.sfSymbol,
      },
    ]),
  );
  catalog.descriptions = descriptions;

  return `${JSON.stringify(catalog, null, 2)}\n`;
}

function catalogValue(token) {
  switch (token.type) {
    case "color":
    case "fontFamily":
    case "shadow":
    case "cubicBezier":
      return cssValue(token);
    case "typography": {
      const { value } = token;
      const fluid = token.extension.web?.fluid;
      return {
        fontFamily: value.fontFamily.map(cssFontFamily).join(", "),
        fontSize: value.fontSize,
        ...(fluid
          ? {
              fluidFontSize: `clamp(${fluid.minimum.value}px, ${formatNumber(fluid.viewportWidth)}vw, ${value.fontSize}px)`,
            }
          : {}),
        fontWeight: value.fontWeight,
        lineHeight: value.lineHeight,
        letterSpacing: value.letterSpacing,
        textCase: textCase(token),
      };
    }
    default:
      return token.value;
  }
}

// TypeScript

export function makeTypeScript(system, icons, sourceLabel, components = []) {
  const web = webTokens(system);
  const webIcons = icons.icons.filter((icon) => icon.platforms.includes("web"));
  const children = (group) =>
    web.paths
      .filter((path) => path.startsWith(`${group}.`))
      .map((path) => [path.slice(group.length + 1), web.light.get(path)]);
  const numbers = (group) =>
    Object.fromEntries(
      children(group).map(([name, token]) => {
        if (name.includes(".")) {
          throw new Error(
            `{${group}.${name}} must be a direct child of ${group}.`,
          );
        }
        return [name, token.value];
      }),
    );
  const colors = Object.fromEntries(
    themes.map((theme) => {
      const values = {};
      for (const [name, token] of children("color")) {
        setPath(values, name.split("."), cssValue(web[theme].get(token.path)));
      }
      return [theme, values];
    }),
  );
  const typeRoles = children("type").map(([name]) => name);

  return `// Generated from ${sourceLabel}. Do not edit directly.

/** Semantic icon names drawn on Web, from packages/design-system/icons.json. */
${tsConst(
  "iconNames",
  webIcons.map((icon) => icon.name),
)}

export type IconName = (typeof iconNames)[number];

export type IconElement = readonly [
  tag: "path" | "circle" | "rect",
  attributes: Readonly<Record<string, string>>,
];

export const iconViewBox = ${JSON.stringify(icons.viewBox)};

export const iconStrokeWidth = ${icons.strokeWidth};

export type IconElements = Readonly<Record<IconName, readonly IconElement[]>>;

${tsConst(
  "iconElements: IconElements",
  Object.fromEntries(webIcons.map((icon) => [icon.name, icon.svg])),
  "",
)}

/** Text roles; each has --mt-type-<role>-font-family, -font-size, -font-weight, -line-height, -letter-spacing, and -text-transform. */
${tsConst("typeRoles", typeRoles)}

export type TypeRole = (typeof typeRoles)[number];

/** Maximum page content widths in px. */
${tsConst("pageWidths", numbers("layout.pageWidth"))}

export type PageWidth = keyof typeof pageWidths;

/** Layout breakpoints in px. Media queries use max-width at the value and min-width one pixel above it. */
${tsConst("breakpoints", numbers("layout.breakpoint"))}

/** Container query widths in px. */
${tsConst("containerWidths", numbers("layout.container"))}

/** Stacking order (z-index) by layer. */
${tsConst("layers", numbers("layout.layer"))}

/** Resolved semantic colors for code that cannot read CSS variables, such as server-rendered images. */
${tsConst("themeColors", colors)}
${componentTypeScript(components, sourceLabel)}`;
}

// Each enum prop becomes a value list and a union type, each spec a defaults object, and every
// spec's specimens join one list that the gallery and its e2e test share.
function componentTypeScript(components, sourceLabel) {
  if (components.length === 0) return "";
  const blocks = components.map((spec) => {
    const props = spec.props.filter((prop) => prop.platforms.includes("web"));
    const lines = [
      `// ${spec.name}, from ${sourceLabel}/components/${spec.file}.`,
    ];
    for (const prop of props.filter(({ kind }) => kind === "enum")) {
      const name = prop.names.web;
      const list = `${lowerFirst(spec.name)}${pascalCase(plural(name))}`;
      lines.push(
        "",
        `/** ${prop.description} */`,
        tsConst(list, prop.values),
        "",
        `export type ${spec.name}${pascalCase(name)} = (typeof ${list})[number];`,
      );
    }
    lines.push(
      "",
      `/** ${spec.name} prop defaults. */`,
      tsConst(
        `${lowerFirst(spec.name)}Defaults`,
        Object.fromEntries(props.map((prop) => [prop.names.web, prop.default])),
      ),
    );
    return lines.join("\n");
  });
  const specimens = components.flatMap((spec) =>
    spec.specimens.map((specimen) => ({
      component: spec.name,
      id: specimen.id,
      description: specimen.description,
      covers: specimen.covers,
    })),
  );
  return `
${blocks.join("\n\n")}

/** Every spec's gallery specimens. The gallery marks each with data-specimen="<id>". */
${tsConst("componentSpecimens", specimens)}

export type ComponentSpecimen = (typeof componentSpecimens)[number];

export type ComponentSpecimenId = ComponentSpecimen["id"];
`;
}

function lowerFirst(value) {
  return value[0].toLowerCase() + value.slice(1);
}

// English plurals for prop names: tone -> tones, status -> statuses, emphasis -> emphases.
export function plural(word) {
  if (/[^aeiou]is$/.test(word)) return word.replace(/is$/, "es");
  if (/(s|x|z|ch|sh)$/.test(word)) return `${word}es`;
  if (/[^aeiou]y$/.test(word)) return word.replace(/y$/, "ies");
  return `${word}s`;
}

// Prints an exported constant, `as const` unless another suffix is given.
export function tsConst(declaration, value, suffix = " as const") {
  const prefix = `export const ${declaration} = `;
  return `${prefix}${tsValue(value, 0, prefix.length, suffix.length + 1)}${suffix};`;
}

// Prints a value as a TypeScript literal, breaking lines like Prettier at 80 columns. `lead` and
// `tail` are the widths of the text before and after the value on its first and last lines.
function tsValue(value, depth = 0, lead = 0, tail = 1) {
  const pad = "  ".repeat(depth + 1);
  const end = "  ".repeat(depth);
  const fits = (inline) =>
    !inline.includes("\n") && lead + inline.length + tail <= 80;
  if (Array.isArray(value)) {
    const inline = tsInline(value);
    if (fits(inline)) return inline;
    const items = value.map((item) => tsValue(item, depth + 1, pad.length));
    return `[\n${items.map((item) => `${pad}${item},`).join("\n")}\n${end}]`;
  }
  if (value !== null && typeof value === "object") {
    const inline = tsInline(value);
    if (fits(inline)) return inline;
    const entries = Object.entries(value).map(([key, item]) => {
      const prefix = `${tsKey(key)}: `;
      return `${prefix}${tsValue(item, depth + 1, pad.length + prefix.length)}`;
    });
    return `{\n${entries.map((entry) => `${pad}${entry},`).join("\n")}\n${end}}`;
  }
  return JSON.stringify(value);
}

function tsInline(value) {
  if (Array.isArray(value)) return `[${value.map(tsInline).join(", ")}]`;
  if (value !== null && typeof value === "object") {
    if (Object.keys(value).length === 0) return "{}";
    return `{ ${Object.entries(value)
      .map(([key, item]) => `${tsKey(key)}: ${tsInline(item)}`)
      .join(", ")} }`;
  }
  return JSON.stringify(value);
}

function tsKey(key) {
  return /^[A-Za-z_$][\w$]*$/.test(key) || /^(0|[1-9]\d*)$/.test(key)
    ? key
    : JSON.stringify(key);
}
