import { readdir, readFile } from "node:fs/promises";
import { join, relative } from "node:path";
import { parse } from "yaml";
import { componentNames } from "./declarations.mjs";
import { tokenName } from "./tokens.mjs";

// Reads component specs and writes each component's README.
//
// Specs live in packages/design-system/components/<name>.yaml, and their schema in
// packages/design-system/schema validates them. This reader checks only what the export relies
// on, and renders any field it does not know as plain text, so the README follows the spec as the
// schema grows.

const specimenId = /^[a-z][a-z0-9]*(-[a-z0-9]+)+$/;

export async function loadSpecs(directory, root) {
  let files;
  try {
    files = (await readdir(directory))
      .filter((file) => /\.ya?ml$/.test(file))
      .sort();
  } catch (error) {
    if (error.code === "ENOENT") return [];
    throw error;
  }
  const specs = [];
  for (const file of files) {
    const path = join(directory, file);
    const label = relative(root, path);
    let spec;
    try {
      spec = parse(await readFile(path, "utf8"));
    } catch (error) {
      throw new Error(`Cannot read ${label}: ${error.message}`);
    }
    specs.push(normalizeSpec(spec, label));
  }
  const names = specs.map((spec) => spec.name);
  const duplicate = names.find((name, index) => names.indexOf(name) !== index);
  if (duplicate) throw new Error(`Two component specs are named ${duplicate}.`);
  return specs;
}

export function normalizeSpec(spec, label) {
  if (!spec || typeof spec !== "object" || Array.isArray(spec)) {
    throw new Error(`${label} must be a YAML mapping.`);
  }
  if (typeof spec.name !== "string" || !/^[A-Z][A-Za-z0-9]*$/.test(spec.name)) {
    throw new Error(`${label}: name must be the component's PascalCase name.`);
  }
  if (typeof spec.purpose !== "string" || !spec.purpose.trim()) {
    throw new Error(`${label}: purpose must be a one-sentence summary.`);
  }
  if (!Array.isArray(spec.specimens) || spec.specimens.length === 0) {
    throw new Error(`${label}: specimens must list at least one specimen.`);
  }
  for (const specimen of spec.specimens) {
    if (typeof specimen?.id !== "string" || !specimenId.test(specimen.id)) {
      throw new Error(`${label}: every specimen needs a kebab-case id.`);
    }
    if (
      typeof specimen.description !== "string" ||
      !specimen.description.trim()
    ) {
      throw new Error(`${label}: specimen ${specimen.id} needs a description.`);
    }
  }
  const ids = spec.specimens.map(({ id }) => id);
  if (new Set(ids).size !== ids.length) {
    throw new Error(`${label}: specimen ids must be unique.`);
  }
  return { ...spec, label };
}

// A spec describes a bundled component when it has the same name. Its Web platform must point at
// the bundled file and list only exports the component bundles.
export function checkSpecAgainstComponent(spec, component) {
  const web = spec.platforms?.web;
  if (!web || web.unavailable) {
    throw new Error(
      `${spec.label} says Web has no ${spec.name}, but catalog.mjs bundles one.`,
    );
  }
  const expected = `apps/web/src/components/${component.source}`;
  if (web.path !== expected) {
    throw new Error(
      `${spec.label} points Web at ${web.path}, but catalog.mjs bundles ${spec.name} from ${expected}.`,
    );
  }
  const names = componentNames(component);
  const missing = (web.symbols ?? []).filter(
    (symbol) => !names.includes(symbol),
  );
  if (missing.length > 0) {
    throw new Error(
      `${spec.label} lists ${missing.join(", ")}, which catalog.mjs does not bundle as ${spec.name} or one of its parts.`,
    );
  }
}

// README of a bundled component

export function componentReadme({
  component,
  spec,
  declarations,
  specimens,
  tokenNames,
}) {
  const lines = [];
  const props = (name) => declarations.props.get(name);
  const defaults = (name) => declarations.defaults.get(name) ?? {};
  const format = formatter(tokenNames);

  if (spec) {
    lines.push(format.prose(spec.purpose));
  } else {
    lines.push(component.summary);
    const documentation = declarations.documentation.get(component.name);
    if (documentation) lines.push("", paragraph(documentation));
    lines.push(
      "",
      "This component has no spec yet, so this page lists its props from the Web source.",
    );
  }
  lines.push(
    "",
    `Render it as \`MemoTrail.${component.name}\`; \`../index.d.ts\` declares its full props.`,
  );

  if (spec) lines.push(...specSections(spec, format));
  lines.push(
    ...propSections(
      component.name,
      props(component.name),
      defaults(component.name),
      spec ? "Web props" : "Props",
    ),
  );
  for (const part of component.parts ?? []) {
    lines.push("", `## ${part.name}`, "", part.note);
    lines.push(
      ...propSections(part.name, props(part.name), defaults(part.name), null),
    );
  }

  lines.push("", "## Specimens", "");
  for (const { id, caption } of specimens)
    lines.push(`- \`${id}\`: ${caption}`);

  lines.push("", "## Source", "");
  if (spec) lines.push(...sources(spec));
  else lines.push(`- Web: \`apps/web/src/components/${component.source}\``);
  return finish(lines);
}

// README of a spec whose component the bundle does not include.
export function specOnlyReadme(spec, reason, tokenNames) {
  const format = formatter(tokenNames);
  const lines = [
    format.prose(spec.purpose),
    "",
    reason,
    ...specSections(spec, format),
  ];
  lines.push("", "## Specimens", "");
  for (const { id, description } of spec.specimens) {
    lines.push(`- \`${id}\`: ${format.prose(description)}`);
  }
  lines.push("", "## Source", "", ...sources(spec));
  return finish(lines);
}

function finish(lines) {
  return `${lines
    .join("\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim()}\n`;
}

const sectionTitles = [
  ["use", "Use"],
  ["avoid", "Avoid"],
  ["anatomy", "Anatomy"],
  ["props", "Props"],
  ["states", "States"],
  ["content", "Content"],
  ["accessibility", "Accessibility"],
  ["platformDifferences", "Platform differences"],
  ["tokens", "Tokens"],
];
const handled = new Set([
  "name",
  "label",
  "purpose",
  "platforms",
  "specimens",
  ...sectionTitles.map(([key]) => key),
]);

function specSections(spec, format) {
  const lines = [];
  const fields = [
    ...sectionTitles,
    ...Object.keys(spec)
      .filter((key) => !handled.has(key) && !key.startsWith("$"))
      .map((key) => [key, sentenceCase(key)]),
  ];
  for (const [key, title] of fields) {
    const value = spec[key];
    if (value === undefined || value === null) continue;
    lines.push("", `## ${title}`, "");
    if (Array.isArray(value) && value.length === 0) lines.push("None.");
    else if (key === "props") lines.push(...specProps(value, format));
    else if (key === "states") lines.push(`${value.map(code).join(", ")}.`);
    else if (key === "tokens") lines.push(...tokenRules(value, format));
    else if (key === "content") lines.push(...content(value, format));
    else if (
      key === "anatomy" &&
      value &&
      typeof value === "object" &&
      !Array.isArray(value)
    ) {
      lines.push(
        ...Object.entries(value).map(
          ([part, item]) => `- ${code(part)}: ${format.any(item)}`,
        ),
      );
    } else if (
      key === "accessibility" &&
      value?.minimumHitTarget === "notInteractive"
    ) {
      lines.push(
        ...format.block({ ...value, minimumHitTarget: "Not interactive." }),
      );
    } else if (key === "platformDifferences") {
      lines.push(
        ...value.map((item) =>
          item?.difference
            ? `- ${format.prose(item.difference)} ${format.prose(item.reason ?? "")}`.trimEnd()
            : `- ${format.any(item)}`,
        ),
      );
    } else lines.push(...format.block(value));
  }
  return lines;
}

function specProps(value, format) {
  const entries = Array.isArray(value)
    ? value.map((prop) => [prop?.name, prop])
    : Object.entries(value);
  if (entries.length === 0) return ["It has no appearance props."];
  const rows = entries.map(([name, prop]) => {
    const values = Array.isArray(prop?.values)
      ? prop.values.map(code).join(", ")
      : prop?.type === "boolean"
        ? `${code(true)}, ${code(false)}`
        : prop?.type
          ? code(prop.type)
          : "";
    const notes = [format.prose(prop?.description ?? "")];
    if (Array.isArray(prop?.platforms)) {
      notes.push(`${prop.platforms.map(platformLabel).join(" and ")} only.`);
    }
    for (const [platform, own] of Object.entries(prop?.platformNames ?? {})) {
      notes.push(`Named ${code(own)} on ${platformLabel(platform)}.`);
    }
    return [
      code(name),
      values,
      prop?.default === undefined ? "" : code(prop.default),
      cell(notes.filter(Boolean).join(" ")),
    ];
  });
  return table(["Prop", "Values", "Default", "Notes"], rows);
}

// Token rules read like the CSS cascade: a rule without `when` always applies, and later rules
// override earlier ones for the same part property.
function tokenRules(rules, format) {
  const lines = [
    "Each rule names the token that draws a part's property; later rules override earlier ones.",
    "",
  ];
  for (const rule of rules) {
    const { when, ...parts } = rule ?? {};
    const condition = when
      ? `When ${Object.entries(when)
          .map(([key, value]) => describeCondition(key, value))
          .join(" and ")}`
      : "Always";
    const styles = Object.entries(parts).map(
      ([part, properties]) =>
        `${code(part)} ${Object.entries(properties ?? {})
          .map(
            ([property, value]) =>
              `${sentenceCase(property).toLowerCase()} ${tokenValue(value, format)}`,
          )
          .join(", ")}`,
    );
    lines.push(`- ${condition}: ${styles.join("; ")}.`);
  }
  return lines;

  function describeCondition(key, value) {
    if (value === true) return `${key} is on`;
    if (value === false) return `${key} is off`;
    if (Array.isArray(value))
      return `${key} is ${value.map(code).join(" or ")}`;
    return `${key} is ${code(value)}`;
  }
}

function tokenValue(value, format) {
  if (typeof value === "string") return format.reference(value);
  if (value && typeof value === "object") {
    const entries = Object.entries(value);
    const shown = entries
      .map(
        ([platform, item]) =>
          `${format.reference(item)} on ${platformLabel(platform)}`,
      )
      .join(" and ");
    return entries.length === 1 ? `${shown} only` : shown;
  }
  return code(value);
}

const contentValues = {
  overflow: {
    truncateTail: "truncates at the tail",
    wrap: "wraps onto the next line",
    perPlatform: "differs by platform, as Platform differences describes",
  },
  casing: {
    sentence: "sentence case",
    title: "title case",
    asWritten: "as written, such as a person's own tag",
  },
};

function content(value, format) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return format.block(value);
  }
  const lines = [];
  for (const [key, item] of Object.entries(value)) {
    if (key === "notes") continue;
    if (key === "lines") {
      lines.push(
        `- Lines: ${item === "unlimited" ? "unlimited" : `at most ${item}`}.`,
      );
    } else if (contentValues[key]?.[item]) {
      lines.push(`- ${sentenceCase(key)}: ${contentValues[key][item]}.`);
    } else {
      lines.push(`- ${sentenceCase(key)}: ${format.any(item)}`);
    }
  }
  if (value.notes) lines.push(...format.block(value.notes));
  return lines;
}

function sources(spec) {
  if (!spec.platforms || typeof spec.platforms !== "object") return [];
  return Object.entries(spec.platforms).map(([platform, item]) => {
    const label = platformLabel(platform);
    if (item?.unavailable)
      return `- ${label}: not available. ${paragraph(item.unavailable)}`;
    if (item?.path) {
      const symbols = Array.isArray(item.symbols)
        ? ` (${item.symbols.join(", ")})`
        : "";
      return `- ${label}: \`${item.path}\`${symbols}`;
    }
    return `- ${label}: ${typeof item === "string" ? `\`${item}\`` : paragraph(JSON.stringify(item))}`;
  });
}

function propSections(name, props, defaults, title) {
  if (!props) throw new Error(`index.d.ts has no props for ${name}.`);
  const lines = title ? ["", `## ${title}`, ""] : [""];
  if (props.own.length === 0) {
    lines.push("It takes no props of its own.");
  } else {
    lines.push(
      ...table(
        ["Prop", "Type", "Default", "Notes"],
        props.own.map((prop) => [
          code(prop.name),
          code(prop.type),
          defaults[prop.name] === undefined ? "" : code(defaults[prop.name]),
          cell(
            [prop.required ? "Required." : null, prop.description || null]
              .filter(Boolean)
              .join(" "),
          ),
        ]),
      ),
    );
  }
  if (props.inheritsFrom) {
    const element =
      props.inheritsFrom === "element"
        ? "the root element's"
        : `a native \`<${props.inheritsFrom}>\``;
    lines.push("", `It also accepts the other attributes of ${element}.`);
  }
  return lines;
}

// Formatting

// Spec text names tokens by their source path, such as {color.accent}. The copy names them like
// the Web variables, so references become the copy's token names. A reference to a group, such
// as a material, becomes the prefix its tokens share.
function formatter(tokenNames) {
  const known = tokenNames ?? new Set();
  const reference = (value) => {
    const match =
      typeof value === "string" && value.match(/^\{([A-Za-z0-9.]+)\}$/);
    if (!match) return code(value);
    const name = tokenName(match[1]);
    if (known.has(name)) return code(name);
    const prefix = `${name}-`;
    if ([...known].some((item) => item.startsWith(prefix)))
      return code(`${prefix}*`);
    return code(name);
  };
  const prose = (value) =>
    paragraph(value).replace(
      /\{([a-z][A-Za-z0-9]*(?:\.[A-Za-z0-9]+)+)\}/g,
      (match) => reference(match),
    );
  const any = (value) => {
    if (value === null || value === undefined) return "";
    if (typeof value === "string") {
      return /^\{[A-Za-z0-9.]+\}$/.test(value)
        ? `${reference(value)}.`
        : prose(value);
    }
    if (typeof value === "number" || typeof value === "boolean")
      return `${code(value)}.`;
    if (Array.isArray(value)) return value.map(any).join(" ");
    return Object.entries(value)
      .map(([key, item]) => `${sentenceCase(key)}: ${any(item)}`)
      .join(" ");
  };
  const block = (value) => {
    if (value === undefined || value === null) return [];
    if (Array.isArray(value)) return value.map((item) => `- ${any(item)}`);
    if (typeof value === "object") {
      return Object.entries(value).map(
        ([key, item]) => `- **${sentenceCase(key)}**: ${any(item)}`,
      );
    }
    return [any(value)];
  };
  return { reference, prose, any, block };
}

function paragraph(value) {
  return String(value)
    .trim()
    .replace(/\s*\n\s*/g, " ");
}

function code(value) {
  const string = typeof value === "string" ? value : JSON.stringify(value);
  return `\`${string.replaceAll("|", "\\|")}\``;
}

function table(headers, rows) {
  return [
    `| ${headers.join(" | ")} |`,
    `| ${headers.map(() => "---").join(" | ")} |`,
    ...rows.map((row) => `| ${row.join(" | ")} |`),
  ];
}

function cell(value) {
  return paragraph(value).replaceAll("|", "\\|");
}

function sentenceCase(key) {
  const words = key.replace(/([a-z0-9])([A-Z])/g, "$1 $2").toLowerCase();
  return words[0].toUpperCase() + words.slice(1);
}

function platformLabel(platform) {
  return { web: "Web", ios: "iOS" }[platform] ?? platform;
}
