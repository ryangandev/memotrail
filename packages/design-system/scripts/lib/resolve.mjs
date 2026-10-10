import { readFile } from "node:fs/promises";
import { relative, resolve } from "node:path";
import { textCases, validators } from "./validators.mjs";
import {
  aliasPath,
  deepEqual,
  describePath,
  hexString,
  isObject,
  isUnit,
} from "./util.mjs";

// Resolves the DTCG 2025.10 resolver once per platform and theme. Tokens may limit themselves
// to one platform, override their value for one platform, and carry MemoTrail settings, all in
// $extensions["com.memotrail"].

export const vendor = "com.memotrail";
export const platforms = ["web", "ios"];
export const themes = ["light", "dark"];
const themeModifier = "theme";

// Platform outputs never receive palette tokens, so components can only use semantic roles.
export const privateGroups = new Set(["palette"]);

const groupExtensionKeys = new Set(["platforms", "ios"]);
const groupIosKeys = new Set(["material"]);
const tokenExtensionKeys = new Set([
  "platforms",
  "ios",
  "web",
  "textCase",
  "mix",
]);
const platformKeys = {
  ios: new Set(["value", "textStyle", "textCase"]),
  web: new Set(["value", "fluid"]),
};
export const iosTextStyles = {
  largeTitle: { size: 34, weight: 400 },
  title: { size: 28, weight: 400 },
  title2: { size: 22, weight: 400 },
  title3: { size: 20, weight: 400 },
  headline: { size: 17, weight: 600 },
  body: { size: 17, weight: 400 },
  callout: { size: 16, weight: 400 },
  subheadline: { size: 15, weight: 400 },
  footnote: { size: 13, weight: 400 },
  caption: { size: 12, weight: 400 },
  caption2: { size: 11, weight: 400 },
};
export const iosMaterials = new Set([
  "ultraThin",
  "thin",
  "regular",
  "thick",
  "ultraThick",
  "bar",
]);

export async function readJson(path, root) {
  try {
    return JSON.parse(await readFile(path, "utf8"));
  } catch (error) {
    throw new Error(`Cannot read ${relative(root, path)}: ${error.message}`);
  }
}

export async function resolveSystem({ resolverPath, tokenDirectory, root }) {
  const document = await readJson(resolverPath, root);
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

  const load = (sources, owner) =>
    loadSources(sources, owner, tokenDirectory, root);
  const definitions = {};
  const themedPaths = {};
  const resolved = Object.fromEntries(
    platforms.map((platform) => [platform, {}]),
  );

  for (const theme of themes) {
    const { documents, contextDocuments } = await orderedDocuments(
      document,
      { [themeModifier]: theme },
      load,
    );
    const merged = resolvePointers(documents.reduce(mergeDocuments, {}));
    const groups = new Map();
    definitions[theme] = {
      tokens: flatten(merged, groups),
      groups,
      groupDescriptions: groupDescriptions(merged),
    };
    themedPaths[theme] = tokenPaths(
      contextDocuments.reduce(mergeDocuments, {}),
    );

    for (const platform of platforms) {
      resolved[platform][theme] = resolvePlatform(
        definitions[theme].tokens,
        platform,
      );
    }
  }

  const [first, ...others] = themes;
  for (const theme of others) {
    if (themedPaths[theme].join(",") !== themedPaths[first].join(",")) {
      throw new Error(
        `The ${first} and ${theme} themes must define the same tokens in the same order.`,
      );
    }
    for (const [path, token] of definitions[first].tokens) {
      const other = definitions[theme].tokens.get(path);
      if (other?.type !== token.type) {
        throw new Error(
          `Token {${path}} must have the same type in every theme.`,
        );
      }
      if (!deepEqual(other.platforms, token.platforms)) {
        throw new Error(
          `Token {${path}} must target the same platforms in every theme.`,
        );
      }
    }
  }

  return {
    name: document.name,
    groups: definitions[first].groups,
    groupDescriptions: definitions[first].groupDescriptions,
    themedPaths: new Set(themedPaths[first]),
    platforms: resolved,
  };
}

async function orderedDocuments(document, input, load) {
  const documents = [];
  const contextDocuments = [];

  for (const entry of document.resolutionOrder ?? []) {
    const { kind, name, definition } = resolutionEntry(document, entry);

    if (kind === "set") {
      documents.push(...(await load(definition.sources, `set ${name}`)));
      continue;
    }

    const context = input[name] ?? definition.default;
    const sources = definition.contexts?.[context];
    if (!sources) {
      throw new Error(`Modifier ${name} has no context ${context}.`);
    }

    const loaded = await load(sources, `modifier ${name}`);
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

async function loadSources(sources, owner, tokenDirectory, root) {
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
      return readJson(resolve(tokenDirectory, source.$ref), root);
    }),
  );
}

// Later sources replace earlier tokens whole; groups merge key by key.
export function mergeDocuments(target, source) {
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

// Replaces every {"$ref": "#/json/pointer"} object with a copy of the value it points to.
// A pointer cannot pass through an alias, because the alias names a token, not a document path.
export function resolvePointers(document) {
  const resolving = new Set();

  const follow = (pointer) => {
    if (!pointer.startsWith("#/")) {
      throw new Error(
        `$ref ${pointer} must be a JSON Pointer into the merged tokens, starting with #/.`,
      );
    }
    if (resolving.has(pointer)) {
      throw new Error(`Circular $ref through ${pointer}.`);
    }
    resolving.add(pointer);

    let node = document;
    const keys = pointer
      .slice(2)
      .split("/")
      .map((key) => key.replaceAll("~1", "/").replaceAll("~0", "~"));
    for (const [index, key] of keys.entries()) {
      if (aliasPath(node)) {
        throw new Error(
          `$ref ${pointer} passes through the alias ${node} at /${keys.slice(0, index).join("/")}. Point at the aliased token's own value instead.`,
        );
      }
      if (!isObject(node) && !Array.isArray(node)) {
        throw new Error(`$ref ${pointer} does not point at a value.`);
      }
      if (!(key in node)) throw new Error(`$ref ${pointer} points at nothing.`);
      node = node[key];
    }

    const value = visit(node);
    resolving.delete(pointer);
    return value;
  };

  const visit = (node) => {
    if (Array.isArray(node)) return node.map(visit);
    if (!isObject(node)) return node;
    if ("$ref" in node) {
      if (Object.keys(node).length !== 1 || typeof node.$ref !== "string") {
        throw new Error(
          `A $ref object must contain only a string $ref, got ${JSON.stringify(node)}.`,
        );
      }
      return follow(node.$ref);
    }
    return Object.fromEntries(
      Object.entries(node).map(([key, value]) => [key, visit(value)]),
    );
  };

  return visit(document);
}

const groupProperties = new Set([
  "$type",
  "$description",
  "$extensions",
  "$deprecated",
]);
const tokenProperties = new Set([...groupProperties, "$value"]);

// Flattens the token tree into source-ordered definitions with inherited types and platforms.
export function flatten(node, groups = new Map(), path = [], inherited = {}) {
  const tokens = new Map();
  const type = node.$type ?? inherited.type;

  for (const key of Object.keys(node)) {
    if (key.startsWith("$") && !groupProperties.has(key)) {
      throw new Error(
        `${describePath(path)}: ${key} is not supported in token groups.`,
      );
    }
  }

  const groupExtension = vendorExtension(node, path);
  for (const key of Object.keys(groupExtension)) {
    if (!groupExtensionKeys.has(key)) {
      throw new Error(
        `${describePath(path)}: group $extensions["${vendor}"].${key} is not supported. Groups accept ${[...groupExtensionKeys].join(" and ")}.`,
      );
    }
  }
  for (const key of Object.keys(groupExtension.ios ?? {})) {
    if (!groupIosKeys.has(key)) {
      throw new Error(
        `${describePath(path)}: group $extensions["${vendor}"].ios.${key} is not supported.`,
      );
    }
  }
  if (groupExtension.ios?.material !== undefined) {
    if (!iosMaterials.has(groupExtension.ios.material)) {
      throw new Error(
        `${describePath(path)}: iOS material must be one of ${[...iosMaterials].join(", ")}.`,
      );
    }
  }
  const groupPlatforms = platformList(
    groupExtension.platforms,
    inherited.platforms ?? platforms,
    path,
  );
  if (path.length > 0) groups.set(path.join("."), groupExtension);

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
      for (const [nestedPath, token] of flatten(child, groups, childPath, {
        type,
        platforms: groupPlatforms,
      })) {
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

    const extension = vendorExtension(child, childPath);
    const tokenPlatforms = platformList(
      extension.platforms,
      groupPlatforms,
      childPath,
    );
    validateTokenExtension(childPath, tokenType, extension, tokenPlatforms);

    tokens.set(childPath.join("."), {
      type: tokenType,
      value: child.$value,
      description: child.$description,
      extension,
      platforms: tokenPlatforms,
    });
  }

  return tokens;
}

// Maps each group path to its $description, so outputs can describe tokens that have none.
function groupDescriptions(node, path = [], descriptions = new Map()) {
  if (path.length > 0 && typeof node.$description === "string") {
    descriptions.set(path.join("."), node.$description);
  }
  for (const [name, child] of Object.entries(node)) {
    if (name.startsWith("$") || !isObject(child) || "$value" in child) continue;
    groupDescriptions(child, [...path, name], descriptions);
  }
  return descriptions;
}

function tokenPaths(node, path = []) {
  const paths = [];
  for (const [name, child] of Object.entries(node)) {
    if (name.startsWith("$") || !isObject(child)) continue;
    if ("$value" in child) paths.push([...path, name].join("."));
    else paths.push(...tokenPaths(child, [...path, name]));
  }
  return paths;
}

function vendorExtension(node, path) {
  const extensions = node.$extensions;
  if (extensions === undefined) return {};
  if (!isObject(extensions)) {
    throw new Error(`${describePath(path)}: $extensions must be an object.`);
  }
  const extension = extensions[vendor] ?? {};
  if (!isObject(extension)) {
    throw new Error(
      `${describePath(path)}: $extensions["${vendor}"] must be an object.`,
    );
  }
  return extension;
}

function platformList(value, inherited, path) {
  if (value === undefined) return inherited;
  if (
    !Array.isArray(value) ||
    value.length === 0 ||
    !value.every((platform) => platforms.includes(platform)) ||
    new Set(value).size !== value.length
  ) {
    throw new Error(
      `${describePath(path)}: platforms must list one or more of ${platforms.join(" and ")}.`,
    );
  }
  const outside = value.filter((platform) => !inherited.includes(platform));
  if (outside.length > 0) {
    throw new Error(
      `${describePath(path)} targets ${outside.join(" and ")}, which its group excludes.`,
    );
  }
  return platforms.filter((platform) => value.includes(platform));
}

function validateTokenExtension(path, type, extension, tokenPlatforms) {
  const where = `${describePath(path)} $extensions["${vendor}"]`;
  for (const key of Object.keys(extension)) {
    if (!tokenExtensionKeys.has(key)) {
      throw new Error(
        `${where}.${key} is not supported. Tokens accept ${[...tokenExtensionKeys].join(", ")}.`,
      );
    }
  }

  for (const platform of platforms) {
    const settings = extension[platform];
    if (settings === undefined) continue;
    if (!isObject(settings)) {
      throw new Error(`${where}.${platform} must be an object.`);
    }
    if (!tokenPlatforms.includes(platform)) {
      throw new Error(
        `${where}.${platform} configures a platform the token is not emitted to.`,
      );
    }
    for (const key of Object.keys(settings)) {
      if (!platformKeys[platform].has(key)) {
        throw new Error(
          `${where}.${platform}.${key} is not supported. Use ${[...platformKeys[platform]].join(", ")}.`,
        );
      }
    }
    if (settings.value !== undefined && type === "typography") {
      if (!isObject(settings.value)) {
        throw new Error(
          `${where}.${platform}.value must list the typography properties it overrides.`,
        );
      }
    }
  }

  if (
    extension.textCase !== undefined ||
    extension.ios?.textCase !== undefined
  ) {
    if (type !== "typography") {
      throw new Error(`${where}.textCase applies to typography tokens only.`);
    }
    for (const value of [extension.textCase, extension.ios?.textCase]) {
      if (value !== undefined && !textCases.has(value)) {
        throw new Error(
          `${where} textCase must be one of ${[...textCases].join(", ")}.`,
        );
      }
    }
  }

  if (type === "typography" && tokenPlatforms.includes("ios")) {
    const style = extension.ios?.textStyle;
    if (style !== "none" && !(style in iosTextStyles)) {
      throw new Error(
        `${where}.ios.textStyle must name the Dynamic Type style the role scales with (${Object.keys(iosTextStyles).join(", ")}), or "none" for a fixed size.`,
      );
    }
  } else if (extension.ios?.textStyle !== undefined) {
    throw new Error(`${where}.ios.textStyle applies to iOS typography only.`);
  }

  if (extension.web?.fluid !== undefined) {
    const fluid = extension.web.fluid;
    if (
      type !== "typography" ||
      !isObject(fluid) ||
      Object.keys(fluid).sort().join(",") !== "minimum,viewportWidth" ||
      !Number.isFinite(fluid.viewportWidth) ||
      fluid.viewportWidth <= 0
    ) {
      throw new Error(
        `${where}.web.fluid must be { minimum: dimension, viewportWidth: vw number } on a typography token.`,
      );
    }
  }

  if (extension.mix !== undefined) {
    const mix = extension.mix;
    if (
      type !== "color" ||
      !isObject(mix) ||
      Object.keys(mix).sort().join(",") !== "colors,weight" ||
      !Array.isArray(mix.colors) ||
      mix.colors.length < 1 ||
      mix.colors.length > 2 ||
      !mix.colors.every((color) => aliasPath(color)) ||
      !isUnit(mix.weight)
    ) {
      throw new Error(
        `${where}.mix must be { colors: one or two color aliases, weight: 0 to 1 } on a color token.`,
      );
    }
  }
}

// Applies platform filtering and overrides, then resolves aliases and validates every value.
export function resolvePlatform(definitions, platform) {
  const tokens = new Map();
  for (const [path, definition] of definitions) {
    if (!definition.platforms.includes(platform)) continue;
    const override = definition.extension[platform]?.value;
    let value = definition.value;
    if (override !== undefined) {
      value =
        definition.type === "typography" && isObject(value)
          ? { ...value, ...override }
          : override;
    }
    tokens.set(path, {
      ...definition,
      value,
      overridden: override !== undefined,
    });
  }

  const resolved = new Map();
  const resolving = new Set();

  const resolveToken = (path, from) => {
    const cached = resolved.get(path);
    if (cached) return cached;

    const token = tokens.get(path);
    if (!token) {
      if (definitions.has(path)) {
        throw new Error(
          `{${from}} references {${path}}, which is not emitted to ${platform}.`,
        );
      }
      throw new Error(`{${from}} references the unknown token {${path}}.`);
    }
    if (resolving.has(path)) {
      throw new Error(`Circular token reference through {${path}}.`);
    }

    resolving.add(path);
    const value = resolveValue(token.type, token.value, path);
    resolving.delete(path);

    const result = {
      path,
      type: token.type,
      value,
      alias: aliasPath(token.value) ?? null,
      description: token.description,
      extension: token.extension,
      platforms: token.platforms,
      overridden: token.overridden,
    };
    resolved.set(path, result);
    return result;
  };

  const resolveValue = (type, value, path) => {
    const target = aliasPath(value);
    if (target) {
      const referenced = resolveToken(target, path);
      if (referenced.type !== type) {
        throw new Error(
          `{${path}} is a ${type} but references the ${referenced.type} {${target}}.`,
        );
      }
      return referenced.value;
    }

    const validate = validators[type];
    if (!validate) throw new Error(`{${path}} has unsupported type ${type}.`);
    return validate(
      value,
      path,
      (nested, nestedType) => resolveValue(nestedType, nested, path),
      { platform },
    );
  };

  for (const path of tokens.keys()) resolveToken(path, path);
  for (const token of resolved.values()) verifyMix(token, resolveToken);

  // Keep source order so generated outputs follow the token files.
  return new Map([...tokens.keys()].map((path) => [path, resolved.get(path)]));
}

// A mix records how a color is derived, like CSS color-mix(in srgb, a weight, b). One color
// means that color at the weight's alpha; two opaque colors mix channel by channel.
function verifyMix(token, resolveToken) {
  const mix = token.extension.mix;
  if (!mix || token.overridden) return;

  const sources = mix.colors.map((color) => {
    const source = resolveToken(aliasPath(color), token.path);
    if (source.type !== "color") {
      throw new Error(`{${token.path}} mixes ${color}, which is not a color.`);
    }
    return source.value;
  });

  let expected;
  if (sources.length === 1) {
    expected = {
      channels: sources[0].channels,
      alpha: Number((sources[0].alpha * mix.weight).toFixed(6)),
    };
  } else {
    if (sources.some((source) => source.alpha !== 1)) {
      throw new Error(
        `{${token.path}} can only verify a mix of two opaque colors.`,
      );
    }
    expected = {
      channels: sources[0].channels.map((channel, index) =>
        Math.round(
          mix.weight * channel + (1 - mix.weight) * sources[1].channels[index],
        ),
      ),
      alpha: 1,
    };
  }

  const actual = token.value;
  if (
    actual.channels.join(",") !== expected.channels.join(",") ||
    Math.abs(actual.alpha - expected.alpha) > 1e-6
  ) {
    throw new Error(
      `{${token.path}} is ${hexString(actual.channels)} at alpha ${actual.alpha}, but its mix of ${mix.colors.join(" and ")} at ${mix.weight} gives ${hexString(expected.channels)} at alpha ${expected.alpha}.`,
    );
  }
}

export function isPublic(path) {
  return !privateGroups.has(path.split(".")[0]);
}
