import { existsSync } from "node:fs";
import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";
import { cardGroups } from "./catalog.mjs";
import { bundleNamespace, maximumBundleBytes } from "./bundle.mjs";
import {
  coreFamilies,
  maximumExtraFamilies,
  maximumExtraTokens,
  tokenNamePattern,
} from "./tokens.mjs";

// Checks an exported project/ tree against the format the Claude Design copy reads. The exporter
// runs it before it reports success, and the tests run it on a fresh export.

const number = String.raw`-?(?:\d+\.?\d*|\.\d+)(?:e-?\d+)?`;
const channel = String.raw`(?:${number}%?|none)`;
export const colorForms = [
  /^#(?:[0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/,
  new RegExp(
    String.raw`^(?:rgba?|hsla?|oklch)\(\s*${channel}(?:\s*,\s*|\s+)${channel}(?:\s*,\s*|\s+)${channel}(?:\s*(?:,|\/)\s*${channel})?\s*\)$`,
  ),
  /^\{[A-Za-z0-9][A-Za-z0-9_.-]{0,63}\}$/,
];
export const lengthForm = new RegExp(
  String.raw`^(?:${number}(?:px|rem|em|%)?|0)$`,
);
export const cardMarker = new RegExp(
  String.raw`^<!-- @dsCard group="(${cardGroups.join("|")})" height=(\d+) -->$`,
);
// The cover sits above the brand book rather than in a group, at 240 to 360 px tall.
export const coverMarker = /^<!-- @dsCard height=(\d+) -->$/;
export const coverHeights = { minimum: 240, maximum: 360 };
const bundleHeader = /^\/\* @ds-bundle: (\{.*\}) \*\/$/;

export function isColor(value) {
  return (
    typeof value === "string" && colorForms.some((form) => form.test(value))
  );
}

export async function validateProject(projectDirectory) {
  const problems = [];
  const fail = (message) => problems.push(message);
  const tokens = JSON.parse(
    await readFile(join(projectDirectory, "tokens.json"), "utf8"),
  );

  // tokens.json
  for (const key of ["name", "version", "meta", "color", "type"]) {
    if (tokens[key] === undefined) fail(`tokens.json has no ${key}.`);
  }
  const themes = tokens.color?.themes?.map((theme) => theme.id) ?? [];
  if (themes.join(",") !== "light,dark")
    fail("tokens.json themes must be light and dark.");

  const families = Object.entries(tokens).filter(
    ([key, value]) =>
      !["name", "version", "meta", "type"].includes(key) &&
      value &&
      typeof value === "object",
  );
  const names = new Map();
  for (const [family, value] of families) {
    if (!Array.isArray(value.tokens)) {
      fail(`${family}.tokens must be a list.`);
      continue;
    }
    for (const token of value.tokens) {
      const where = `${family} token ${token?.name}`;
      if (!token || typeof token !== "object") {
        fail(`${family} has a token that is not an object.`);
        continue;
      }
      const keys = Object.keys(token).sort().join(",");
      if (keys !== "name,usage,value")
        fail(`${where} must have exactly name, value, and usage.`);
      if (!tokenNamePattern.test(token.name))
        fail(`${where} has an invalid name.`);
      if (names.has(token.name))
        fail(
          `${token.name} is in both ${names.get(token.name)} and ${family}.`,
        );
      names.set(token.name, family);
      if (typeof token.usage !== "string" || token.usage.trim().length < 3) {
        fail(`${where} has no usage.`);
      }
      checkValue(family, token, themes, fail);
    }
  }
  for (const token of tokens.color?.tokens ?? []) {
    for (const theme of themes) {
      const alias = token.value?.[theme]?.match(/^\{(.+)\}$/)?.[1];
      if (alias && names.get(alias) !== "color") {
        fail(
          `color token ${token.name} aliases ${alias}, which is not a color.`,
        );
      }
    }
  }

  const extras = families.filter(
    ([family]) => !coreFamilies.includes(family) && family !== "color",
  );
  if (extras.length > maximumExtraFamilies) {
    fail(
      `tokens.json has ${extras.length} extra families; the copy accepts ${maximumExtraFamilies}.`,
    );
  }
  for (const [family, value] of extras) {
    if ((value.tokens?.length ?? 0) > maximumExtraTokens) {
      fail(
        `${family} has ${value.tokens.length} tokens; the copy accepts ${maximumExtraTokens}.`,
      );
    }
  }
  for (const family of coreFamilies) {
    if (!tokens[family]) fail(`tokens.json has no ${family} family.`);
  }

  // type
  const type = tokens.type ?? {};
  if (!Array.isArray(type.fonts)) fail("type.fonts must be a list.");
  for (const [key, stack] of Object.entries(type.families ?? {})) {
    if (typeof stack !== "string" || /var\(|url\(/.test(stack))
      fail(`type family ${key} must be a plain CSS stack.`);
  }
  for (const group of type.groups ?? []) {
    if (!type.families?.[group.family])
      fail(`type group ${group.name} uses an unknown family ${group.family}.`);
    for (const style of group.styles ?? []) {
      const where = `type style ${style.name}`;
      if (!tokenNamePattern.test(style.name ?? ""))
        fail(`${where} has an invalid name.`);
      if (!lengthForm.test(style.fontSize ?? ""))
        fail(`${where} has an invalid fontSize.`);
      if (typeof style.fontWeight !== "number")
        fail(`${where} needs a numeric fontWeight.`);
      if (
        typeof style.lineHeight !== "number" &&
        !lengthForm.test(String(style.lineHeight))
      ) {
        fail(`${where} has an invalid lineHeight.`);
      }
      if (
        style.letterSpacing !== undefined &&
        !lengthForm.test(style.letterSpacing)
      ) {
        fail(`${where} has an invalid letterSpacing.`);
      }
    }
  }

  // Components
  const componentDirectory = join(projectDirectory, "components");
  const script = await readFile(join(componentDirectory, "bundle.js"), "utf8");
  const css = await readFile(join(componentDirectory, "bundle.css"), "utf8");
  const header = script.split("\n", 1)[0].match(bundleHeader);
  let listed = [];
  if (!header) {
    fail("bundle.js must start with the @ds-bundle header.");
  } else {
    const meta = JSON.parse(header[1]);
    if (meta.format !== 4 || meta.namespace !== bundleNamespace) {
      fail(
        "The bundle header must declare format 4 and the MemoTrail namespace.",
      );
    }
    listed = meta.components.map((component) => component.name);
  }
  if (/<\/script/i.test(script)) fail("bundle.js contains </script.");
  if (script.includes("<!--")) fail("bundle.js contains <!--.");
  if (/^\s*import[\s{(*]/m.test(script) || /\bimport\(/.test(script))
    fail("bundle.js imports a module.");
  if (Buffer.byteLength(script) > maximumBundleBytes)
    fail("bundle.js is over the size limit.");
  for (const name of declaredVariables(css)) {
    if (names.has(name))
      fail(`bundle.css redeclares --${name}, which tokens.json declares.`);
  }

  const folders = (await readdir(componentDirectory, { withFileTypes: true }))
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name);
  for (const folder of folders) {
    const readme = join(componentDirectory, folder, "README.md");
    const preview = join(componentDirectory, folder, "preview.html");
    if (folder !== "Cover" && !existsSync(readme))
      fail(`${folder} has no README.md.`);
    if (!existsSync(preview)) {
      fail(`${folder} has no preview.html.`);
      continue;
    }
    const firstLine = (await readFile(preview, "utf8")).split("\n", 1)[0];
    if (folder === "Cover") {
      const height = Number(firstLine.match(coverMarker)?.[1]);
      if (!(height >= coverHeights.minimum && height <= coverHeights.maximum))
        fail(
          `Cover/preview.html needs <!-- @dsCard height=N --> with N from ${coverHeights.minimum} to ${coverHeights.maximum}.`,
        );
    } else if (!cardMarker.test(firstLine))
      fail(`${folder}/preview.html has no valid @dsCard marker.`);
  }
  return { problems, listed, folders, names, tokens };
}

function checkValue(family, token, themes, fail) {
  const where = `${family} token ${token.name}`;
  const { value } = token;
  const plain = (item) => {
    if (typeof item === "number") return true;
    if (typeof item !== "string" || !item.trim()) return false;
    return !/var\(|url\(|color-mix\(/i.test(item);
  };
  if (family === "color") {
    if (
      !value ||
      typeof value !== "object" ||
      themes.some((theme) => !isColor(value[theme]))
    ) {
      fail(
        `${where} needs a hex, rgb(), rgba(), hsl(), oklch(), or alias value in every theme.`,
      );
    }
    return;
  }
  if (family === "shadow") {
    const values =
      typeof value === "object" && value
        ? themes.map((theme) => value[theme])
        : [value];
    if (!values.every(plain))
      fail(`${where} needs a plain CSS shadow in every theme.`);
    return;
  }
  if (["spacing", "radius"].includes(family)) {
    if (!lengthForm.test(String(value))) fail(`${where} must be a length.`);
    return;
  }
  if (!plain(value))
    fail(`${where} must be a plain CSS value without var() or url().`);
}

function declaredVariables(css) {
  return [...css.matchAll(/(?:^|[;{\s])--([A-Za-z0-9_-]+)\s*:/g)].map(
    (match) => match[1],
  );
}
