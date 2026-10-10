import { platforms, themes } from "./resolve.mjs";
import { aliasPath, hexString, isObject } from "./util.mjs";

// WCAG 2.2 AA contrast for text. Body text needs 4.5:1 and large text 3:1, where large means at
// least 24px, or at least 18.66px at a bold weight. Each check names its text role, so the
// threshold follows the role's size and weight on each platform.

const label = "contrast.json";
const largeSize = 24;
const largeBoldSize = 18.66;

export function checkContrast(manifest, system) {
  const { checks, exceptions } = parseManifest(manifest);
  const results = [];

  for (const check of checks) {
    for (const platform of platforms) {
      for (const theme of themes) {
        const tokens = system.platforms[platform][theme];
        const needed = [check.text, check.role, ...check.on.flat()];
        if (!needed.every((path) => tokens.has(path))) continue;

        const role = tokens.get(check.role);
        if (role.type !== "typography") {
          throw new Error(`${label}: {${check.role}} is not a text role.`);
        }
        const large =
          role.value.fontSize >= largeSize ||
          (role.value.fontSize >= largeBoldSize &&
            role.value.fontWeight >= 700);
        const minimum = large ? 3 : 4.5;

        for (const stack of check.on) {
          const background = composite(
            stack.map((path) => color(tokens, path)),
            stack,
          );
          const text = over(color(tokens, check.text), background);
          const ratio = contrastRatio(text, background);
          results.push({
            platform,
            theme,
            text: check.text,
            role: check.role,
            on: stack,
            ratio,
            minimum,
            passes: ratio >= minimum,
            background: hexString(background),
          });
        }
      }
    }
  }

  const failures = results.filter((result) => !result.passes);
  const unexplained = failures.filter(
    (failure) => !exceptions.some((exception) => matches(exception, failure)),
  );
  const stale = exceptions.flatMap((exception) =>
    exception.on.flatMap((stack) =>
      exception.themes
        .filter(
          (theme) =>
            !failures.some((failure) =>
              matches({ ...exception, on: [stack], themes: [theme] }, failure),
            ),
        )
        .map((theme) => ({ exception, stack, theme })),
    ),
  );

  const problems = [
    ...unexplained.map(
      (failure) =>
        `${describe(failure)} is ${failure.ratio.toFixed(2)}:1 in ${failure.theme} on ${failure.platform}; needs ${failure.minimum}:1. Fix the colors or add a named exception with a reason.`,
    ),
    ...stale.map(
      ({ exception, stack, theme }) =>
        `The exception "${exception.name}" covers {${exception.text}} on ${stack.map((path) => `{${path}}`).join(" over ")} in ${theme}, which passes. Remove it there.`,
    ),
  ];
  return {
    results,
    exceptions,
    error:
      problems.length > 0
        ? `WCAG AA contrast check failed:\n${problems.join("\n")}`
        : null,
  };
}

function parseManifest(manifest) {
  if (!isObject(manifest)) throw new Error(`${label} must be an object.`);
  for (const key of Object.keys(manifest)) {
    if (!["$description", "checks", "exceptions"].includes(key)) {
      throw new Error(`${label}: unknown property ${key}.`);
    }
  }
  if (!Array.isArray(manifest.checks) || manifest.checks.length === 0) {
    throw new Error(`${label}: checks must list one or more checks.`);
  }

  const checks = manifest.checks.map((check, index) => {
    const where = `${label}: check ${index + 1}`;
    if (
      !isObject(check) ||
      Object.keys(check).sort().join(",") !== "on,role,text"
    ) {
      throw new Error(`${where} must be { text, role, on }.`);
    }
    if (!Array.isArray(check.on) || check.on.length === 0) {
      throw new Error(`${where} on must list one or more backgrounds.`);
    }
    return {
      text: reference(check.text, where),
      role: reference(check.role, where),
      on: check.on.map((stack) => parseStack(stack, where)),
    };
  });

  const exceptions = (manifest.exceptions ?? []).map((exception, index) => {
    const where = `${label}: exception ${index + 1}`;
    if (!isObject(exception)) throw new Error(`${where} must be an object.`);
    for (const key of Object.keys(exception)) {
      if (!["name", "text", "on", "themes", "reason"].includes(key)) {
        throw new Error(`${where} has unknown property ${key}.`);
      }
    }
    if (typeof exception.name !== "string" || !exception.name) {
      throw new Error(`${where} needs a name.`);
    }
    if (typeof exception.reason !== "string" || exception.reason.length < 20) {
      throw new Error(`${where} (${exception.name}) needs a reason.`);
    }
    const exceptionThemes = exception.themes ?? themes;
    if (
      !Array.isArray(exceptionThemes) ||
      !exceptionThemes.every((theme) => themes.includes(theme))
    ) {
      throw new Error(`${where} themes must list ${themes.join(" or ")}.`);
    }
    return {
      name: exception.name,
      reason: exception.reason,
      text: reference(exception.text, where),
      on: (Array.isArray(exception.on) ? exception.on : [exception.on]).map(
        (stack) => parseStack(stack, where),
      ),
      themes: exceptionThemes,
    };
  });

  const names = exceptions.map((exception) => exception.name);
  if (new Set(names).size !== names.length) {
    throw new Error(`${label}: exception names must be unique.`);
  }

  return { checks, exceptions };
}

// "{color.dangerTint} over {color.surface}" lists layers from top to bottom.
function parseStack(value, where) {
  if (typeof value !== "string") {
    throw new Error(`${where} backgrounds must be color references.`);
  }
  return value.split(" over ").map((part) => reference(part.trim(), where));
}

function reference(value, where) {
  const path = aliasPath(value);
  if (!path) {
    throw new Error(
      `${where}: ${JSON.stringify(value)} is not a token reference.`,
    );
  }
  return path;
}

function color(tokens, path) {
  const token = tokens.get(path);
  if (token.type !== "color") {
    throw new Error(`${label}: {${path}} is not a color.`);
  }
  return token.value;
}

// Composites translucent layers onto the bottom layer, which must be opaque.
function composite(layers, stack) {
  const base = layers.at(-1);
  if (base.alpha !== 1) {
    throw new Error(
      `${label}: the bottom of ${stack.map((path) => `{${path}}`).join(" over ")} must be opaque.`,
    );
  }
  return layers
    .slice(0, -1)
    .reduceRight((below, layer) => over(layer, below), base.channels);
}

function over(layer, below) {
  return layer.channels.map((channel, index) =>
    Math.round(layer.alpha * channel + (1 - layer.alpha) * below[index]),
  );
}

export function relativeLuminance(channels) {
  const [red, green, blue] = channels.map((channel) => {
    const value = channel / 255;
    return value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * red + 0.7152 * green + 0.0722 * blue;
}

export function contrastRatio(a, b) {
  const [lighter, darker] = [relativeLuminance(a), relativeLuminance(b)].sort(
    (x, y) => y - x,
  );
  return (lighter + 0.05) / (darker + 0.05);
}

function matches(exception, failure) {
  return (
    exception.text === failure.text &&
    exception.on.some((stack) => stack.join(">") === failure.on.join(">")) &&
    exception.themes.includes(failure.theme)
  );
}

function describe(result) {
  return `{${result.text}} on ${result.on.map((path) => `{${path}}`).join(" over ")} as {${result.role}}`;
}
