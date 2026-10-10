// Compiles an exported tokens.json into CSS the way the Claude Design copy does, so previews can
// be checked against the same variables the copy serves.
//
// The first theme's colors and shadows go under :root and its own data-theme selector, every other
// theme overrides them under its data-theme selector, and the other families go under :root. An
// alias such as {mt-color-accent} becomes var(--mt-color-accent).

const themedFamilies = new Set(["color", "shadow"]);
const skipped = new Set(["name", "version", "meta", "type"]);

export function compileTokens(tokens) {
  const themes = tokens.color.themes.map((theme) => theme.id);
  const [first, ...others] = themes;
  const themed = Object.fromEntries(themes.map((theme) => [theme, []]));
  const root = [];

  for (const [family, value] of Object.entries(tokens)) {
    if (skipped.has(family) || !Array.isArray(value?.tokens)) continue;
    for (const token of value.tokens) {
      const themedValue =
        themedFamilies.has(family) &&
        token.value &&
        typeof token.value === "object";
      if (themedValue) {
        for (const theme of themes) {
          themed[theme].push(declaration(token.name, token.value[theme]));
        }
      } else if (themedFamilies.has(family)) {
        themed[first].push(declaration(token.name, token.value));
      } else {
        root.push(declaration(token.name, token.value));
      }
    }
  }

  return [
    block(`:root,\n[data-theme="${first}"]`, themed[first]),
    ...others.map((theme) => block(`[data-theme="${theme}"]`, themed[theme])),
    block(":root", root),
  ].join("\n\n");
}

function declaration(name, value) {
  const css = String(value).replace(
    /\{([A-Za-z0-9][A-Za-z0-9_.-]*)\}/g,
    "var(--$1)",
  );
  return `  --${name}: ${css};`;
}

function block(selector, lines) {
  return `${selector} {\n${lines.join("\n")}\n}`;
}
