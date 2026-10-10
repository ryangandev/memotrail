import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { webTokens } from "../lib/web.mjs";
import { describe, tokenName } from "./tokens.mjs";

// Writes the copy's README.md, the brand book, from brand-book.md next to this file.
//
// The template holds the hand-written rules. Every {{placeholder}} in it is a table or list built
// here from the token sources, contrast.json, icons.json, and the component catalog, so the facts
// cannot drift from the repository.

export const brandBookTemplate = join(
  dirname(fileURLToPath(import.meta.url)),
  "brand-book.md",
);

// The color roles the brand book tables; every other color is in tokens.json with its usage.
const mainColors = [
  "canvas",
  "surface",
  "surfaceRaised",
  "surfaceSubtle",
  "ink",
  "inkMuted",
  "inkFaint",
  "border",
  "borderStrong",
  "accent",
  "accentHover",
  "accentSubtle",
  "accentInk",
  "warm",
  "warmSubtle",
  "success",
  "successSubtle",
  "warning",
  "warningSubtle",
  "danger",
  "dangerSubtle",
  "info",
  "infoSubtle",
  "scrim",
  "inverseSurface",
  "inverseInk",
].map((name) => `color.${name}`);

export async function makeReadme({
  system,
  contrast,
  icons,
  tokens,
  components,
  specOnly,
}) {
  const template = await readFile(brandBookTemplate, "utf8");
  const web = webTokens(system);
  const values = new Map(
    Object.values(tokens)
      .flatMap((family) => family?.tokens ?? [])
      .map((token) => [token.name, token.value]),
  );
  const value = (path) => {
    const name = tokenName(path);
    if (!values.has(name)) throw new Error(`tokens.json has no ${name}.`);
    return values.get(name);
  };
  const paths = (prefix) => web.paths.filter((path) => path.startsWith(prefix));
  const own = (path) => web.light.get(path).description?.trim() ?? "";
  const use = (path) => describe(path, web.light.get(path), system);
  const tokenRows = (prefix, notes = use) =>
    paths(prefix).map((path) => [
      code(tokenName(path)),
      shown(value(path)),
      cell(notes(path)),
    ]);

  const sections = {
    contrastExceptions: () =>
      contrast.exceptions.map(
        (exception) =>
          `- **${exception.name}** (${exception.themes.join(" and ")}): ${code(tokenName(exception.text))} on ${exception.on
            .map((stack) =>
              stack.map((path) => code(tokenName(path))).join(" over "),
            )
            .join(", ")}. ${exception.reason}`,
      ),

    colorRoles: () => {
      const colors = paths("color.").filter(
        (path) => web.light.get(path).type === "color",
      );
      return [
        ...table(
          ["Token", "Light", "Dark", "Use"],
          mainColors.map((path) => {
            if (!web.light.has(path))
              throw new Error(`{${path}} is gone; update mainColors.`);
            const { light, dark } = value(path);
            return [
              code(tokenName(path)),
              code(light),
              code(dark),
              cell(use(path)),
            ];
          }),
        ),
        "",
        `tokens.json lists all ${tokens.color.tokens.length} colors with their usage: these, ${colors.length - mainColors.length} more specific roles, and the state, material, and elevation colors.`,
      ];
    },

    fontFamilies: () =>
      table(
        ["Family", "Stack", "Use"],
        Object.entries(tokens.type.families).map(([key, stack]) => [
          code(key),
          code(stack),
          cell(use(`font.family.${key}`)),
        ]),
      ),

    textRoles: () =>
      table(
        ["Role", "Family", "Size", "Line height", "Weight", "Use"],
        tokens.type.groups.flatMap((group) =>
          group.styles.map((style) => [
            code(style.name),
            group.name,
            style.letterSpacing
              ? `${style.fontSize}, ${style.letterSpacing} tracking`
              : style.fontSize,
            String(style.lineHeight),
            String(style.fontWeight),
            cell(style.usage),
          ]),
        ),
      ),

    spacing: () =>
      table(
        ["Token", "Value"],
        paths("space.").map((path) => [
          code(tokenName(path)),
          code(value(path)),
        ]),
      ),

    radius: () => table(["Token", "Value", "Use"], tokenRows("radius.")),

    elevation: () => {
      const levels = [...system.groups.keys()].filter((key) =>
        /^elevation\.[^.]+$/.test(key),
      );
      const ref = (path) =>
        web.light.has(path) ? code(tokenName(path)) : "none";
      return [
        ...table(
          ["Level", "Surface", "Shadow", "Use"],
          levels.map((level) => [
            level.split(".")[1],
            ref(`${level}.surface`),
            ref(`${level}.shadow`),
            cell(sentence(system.groupDescriptions.get(level))),
          ]),
        ),
        "",
        "Shadows for specific parts:",
        "",
        ...table(
          ["Token", "Use"],
          paths("shadow.").map((path) => [
            code(tokenName(path)),
            cell(use(path)),
          ]),
        ),
      ];
    },

    materials: () => {
      const materials = [...system.groups].filter(([key]) =>
        /^material\.[^.]+$/.test(key),
      );
      return table(
        ["Material", "Tint", "Blur", "iOS", "Use"],
        materials.map(([key, group]) => {
          const tint = `${key}.tint`;
          return [
            code(tokenName(key)),
            web.light.has(tint) ? code(tokenName(tint)) : "",
            code(value(`${key}.blur`)),
            group.ios?.material
              ? `System ${group.ios.material} material`
              : "Web only",
            cell(sentence(system.groupDescriptions.get(key))),
          ];
        }),
      );
    },

    motion: () => table(["Token", "Value", "Use"], tokenRows("motion.")),

    states: () =>
      table(
        ["Token", "Value", "Use"],
        [
          ...tokenRows("state.focus."),
          ...tokenRows("state.hover."),
          ...tokenRows("state.selected."),
          ...tokenRows("state.disabled.", own),
        ],
      ),

    layout: () =>
      table(
        ["Token", "Value", "Use"],
        [...tokenRows("layout.pageWidth."), ...tokenRows("layout.pageGutter.")],
      ),

    breakpoints: () => [
      `- Breakpoints: ${paths("layout.breakpoint.")
        .map((path) => code(tokenName(path)))
        .join(", ")}.`,
      `- Container query widths: ${paths("layout.container.")
        .map((path) => code(tokenName(path)))
        .join(", ")}.`,
    ],

    layers: () =>
      table(["Token", "Value", "Use"], tokenRows("layout.layer.", own)),

    icons: () =>
      table(
        ["Name", "SF Symbol", "Web", "Use"],
        icons.icons.map((icon) => [
          code(icon.name),
          icon.platforms.includes("ios") ? code(icon.sfSymbol) : "",
          icon.platforms.includes("web") ? "yes" : "",
          cell(icon.description),
        ]),
      ),

    components: () => [
      ...table(
        ["Component", "Card group", "Summary"],
        components.map((component) => [
          `[${component.name}](components/${component.name}/README.md)`,
          component.group,
          cell(component.summary),
        ]),
      ),
      ...(specOnly.length > 0
        ? [
            "",
            "These have a spec but no bundled Web component, so their folders hold only a README:",
            "",
            ...specOnly.map(
              (spec) =>
                `- [${spec.name}](components/${spec.name}/README.md): ${firstSentence(spec.purpose)}`,
            ),
          ]
        : []),
    ],
  };

  const used = new Set();
  const readme = template.replace(/\{\{(\w+)\}\}/g, (match, key) => {
    if (!sections[key])
      throw new Error(`brand-book.md uses an unknown placeholder ${match}.`);
    used.add(key);
    return sections[key]().join("\n");
  });
  const unused = Object.keys(sections).filter((key) => !used.has(key));
  if (unused.length > 0) {
    throw new Error(
      `brand-book.md lacks the placeholders ${unused.join(", ")}.`,
    );
  }
  return readme;
}

function table(headers, rows) {
  return [
    `| ${headers.join(" | ")} |`,
    `| ${headers.map(() => "---").join(" | ")} |`,
    ...rows.map((row) => `| ${row.join(" | ")} |`),
  ];
}

function code(value) {
  const string = typeof value === "string" ? value : JSON.stringify(value);
  return `\`${string.replaceAll("|", "\\|")}\``;
}

// A themed value shows both themes unless they match.
function shown(value) {
  if (value && typeof value === "object") {
    return value.light === value.dark
      ? code(value.light)
      : `${code(value.light)} light, ${code(value.dark)} dark`;
  }
  return code(value);
}

function cell(value) {
  return String(value)
    .trim()
    .replace(/\s*\n\s*/g, " ")
    .replaceAll("|", "\\|");
}

function sentence(text) {
  if (!text) return "";
  const trimmed = text.trim();
  return /[.!?]$/.test(trimmed) ? trimmed : `${trimmed}.`;
}

function firstSentence(text) {
  const flat = String(text).trim().replace(/\s+/g, " ");
  const match = flat.match(/^.*?[.!?](?=\s|$)/);
  return match ? match[0] : flat;
}
