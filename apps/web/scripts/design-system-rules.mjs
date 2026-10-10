// Rules that keep Web styles on the generated design tokens. check-design-system.mjs runs them
// over every stylesheet and script in src. Each finding names the line and, when one exists,
// the token that renders the same value.

// Parsing

// Splits a stylesheet into declarations and at-rules with their line numbers. Comments,
// strings, and parentheses never end a declaration.
export function parseCss(css) {
  const declarations = [];
  const atRules = [];
  const blocks = [];
  let buffer = "";
  let start = 0;
  let line = 1;
  let depth = 0;

  const flush = (opensBlock) => {
    const text = buffer.trim();
    const at = start;
    buffer = "";
    start = 0;
    if (!text) {
      if (opensBlock) blocks.push("");
      return;
    }
    if (opensBlock) blocks.push(text);
    if (text.startsWith("@")) {
      const [, name, params] = text.match(/^@([\w-]+)\s*([\s\S]*)$/);
      atRules.push({ name, params: params.trim(), line: at });
      return;
    }
    const colon = text.indexOf(":");
    if (opensBlock || colon < 0) return;
    declarations.push({
      property: text.slice(0, colon).trim().toLowerCase(),
      value: text.slice(colon + 1).trim(),
      line: at,
      selector: blocks.at(-1) ?? "",
    });
  };

  for (let index = 0; index < css.length; index += 1) {
    const char = css[index];
    if (char === "/" && css[index + 1] === "*") {
      const end = css.indexOf("*/", index + 2);
      const stop = end < 0 ? css.length : end + 2;
      line += countLines(css.slice(index, stop));
      index = stop - 1;
      continue;
    }
    if (!start && /\S/.test(char)) start = line;
    if (char === "\n") line += 1;
    if (char === '"' || char === "'") {
      let end = index + 1;
      while (end < css.length && css[end] !== char) {
        if (css[end] === "\\") end += 1;
        end += 1;
      }
      const text = css.slice(index, end + 1);
      line += countLines(text);
      buffer += text;
      index = end;
      continue;
    }
    if (char === "(") depth += 1;
    if (char === ")") depth = Math.max(0, depth - 1);
    if (depth === 0 && (char === "{" || char === ";" || char === "}")) {
      flush(char === "{");
      if (char === "}") blocks.pop();
      continue;
    }
    buffer += char;
  }
  flush(false);
  return { declarations, atRules };
}

function countLines(text) {
  return text.split("\n").length - 1;
}

// Removes var() references, including any fallback, so only literal text remains.
export function withoutVariables(value) {
  let result = "";
  for (let index = 0; index < value.length; index += 1) {
    if (!value.startsWith("var(", index)) {
      result += value[index];
      continue;
    }
    for (let depth = 0; index < value.length; index += 1) {
      if (value[index] === "(") depth += 1;
      if (value[index] === ")" && --depth === 0) break;
    }
    result += " ";
  }
  return result
    .replace(/"[^"]*"|'[^']*'/g, '""')
    .replace(/!important/g, "")
    .trim();
}

// Tokens

// Reads every --mt-* variable from the generated stylesheet and resolves references in each
// theme, so a token can be found by the value it renders. A literal renders the same in every
// theme, so it only matches a token whose value is that literal in both themes.
export function readTokens(generatedCss) {
  const themes = { light: new Map(), dark: new Map() };
  for (const { property, value, selector } of parseCss(generatedCss)
    .declarations) {
    if (!property.startsWith("--mt-")) continue;
    const dark = /\[data-theme="dark"\]|:not\(\[data-theme="light"\]\)/.test(
      selector,
    );
    const light = !dark && /\[data-theme="light"\]/.test(selector);
    if (!dark) themes.light.set(property, value);
    if (!light) themes.dark.set(property, value);
  }
  const resolve = (theme, value, seen) =>
    value.replace(/var\((--mt-[\w-]+)\)/g, (whole, name) =>
      seen.has(name) || !theme.has(name)
        ? whole
        : resolve(theme, theme.get(name), new Set([...seen, name])),
    );
  const values = [...themes.light.keys()].map((name) => [
    name,
    new Set(
      Object.values(themes).map((theme) =>
        normalize(resolve(theme, theme.get(name), new Set([name]))),
      ),
    ),
  ]);
  return {
    names: new Set(themes.light.keys()),
    // Tokens matching one of the patterns whose value is one of the candidate spellings.
    find(patterns, candidates) {
      const wanted = candidates.map(normalize);
      return values
        .filter(
          ([name, set]) =>
            patterns.some((pattern) => pattern.test(name)) &&
            set.size === 1 &&
            wanted.some((value) => set.has(value)),
        )
        .map(([name]) => name);
    },
  };
}

function normalize(value) {
  return value.trim().toLowerCase().replace(/\s+/g, " ");
}

function suggestion(tokens, patterns, candidates) {
  const found = tokens.find(patterns, candidates);
  return found.length
    ? ` Use ${found.map((name) => `var(${name})`).join(" or ")}.`
    : "";
}

// Literal lengths with a unit. Unitless numbers are multipliers or zero, and percentages and
// viewport units are proportions rather than design values.
const lengthPattern = /(?<![\w.#-])-?(?:\d*\.)?\d+(px|r?em)(?![\w-])/g;

function lengths(value) {
  return [...withoutVariables(value).matchAll(lengthPattern)]
    .map((match) => match[0])
    .filter((length) => Number.parseFloat(length) !== 0);
}

// Spellings of a length a token could have.
function spellings(length) {
  const positive = length.replace(/^-/, "");
  const number = Number.parseFloat(positive);
  return positive.endsWith("rem") ? [`${number * 16}px`] : [positive];
}

// Typography

const roleProperty = (property) =>
  new RegExp(`^--mt-type-[\\w-]+-${property}$`);

const typography = {
  "font-family": {
    allowed: ["inherit"],
    patterns: [/^--mt-font-family-/, roleProperty("font-family")],
  },
  "font-size": {
    allowed: ["inherit", "0"],
    patterns: [/^--mt-font-size-/, roleProperty("font-size")],
  },
  "font-weight": {
    allowed: ["inherit"],
    patterns: [/^--mt-font-weight-/, roleProperty("font-weight")],
  },
  "line-height": {
    allowed: ["inherit", "normal", "0"],
    patterns: [/^--mt-line-height-/, roleProperty("line-height")],
  },
  "letter-spacing": {
    allowed: ["inherit", "normal", "0"],
    patterns: [roleProperty("letter-spacing")],
  },
};

function checkTypography({ property, value }, tokens) {
  const rule = typography[property];
  const literal = withoutVariables(value).replace(/\s+/g, " ");
  if (!literal || rule.allowed.includes(literal)) return [];
  const candidates = [literal, ...spellings(literal)];
  if (property === "font-weight") {
    candidates.push({ normal: "400", bold: "700" }[literal] ?? literal);
  }
  return [
    `literal ${property} ${literal}.${suggestion(tokens, rule.patterns, candidates)}`,
  ];
}

// Color

const namedColors = new Set(
  "aliceblue antiquewhite aqua aquamarine azure beige bisque black blanchedalmond blue blueviolet brown burlywood cadetblue chartreuse chocolate coral cornflowerblue cornsilk crimson cyan darkblue darkcyan darkgoldenrod darkgray darkgreen darkgrey darkkhaki darkmagenta darkolivegreen darkorange darkorchid darkred darksalmon darkseagreen darkslateblue darkslategray darkslategrey darkturquoise darkviolet deeppink deepskyblue dimgray dimgrey dodgerblue firebrick floralwhite forestgreen fuchsia gainsboro ghostwhite gold goldenrod gray green greenyellow grey honeydew hotpink indianred indigo ivory khaki lavender lavenderblush lawngreen lemonchiffon lightblue lightcoral lightcyan lightgoldenrodyellow lightgray lightgreen lightgrey lightpink lightsalmon lightseagreen lightskyblue lightslategray lightslategrey lightsteelblue lightyellow lime limegreen linen magenta maroon mediumaquamarine mediumblue mediumorchid mediumpurple mediumseagreen mediumslateblue mediumspringgreen mediumturquoise mediumvioletred midnightblue mintcream mistyrose moccasin navajowhite navy oldlace olive olivedrab orange orangered orchid palegoldenrod palegreen paleturquoise palevioletred papayawhip peachpuff peru pink plum powderblue purple rebeccapurple red rosybrown royalblue saddlebrown salmon sandybrown seagreen seashell sienna silver skyblue slateblue slategray slategrey snow springgreen steelblue tan teal thistle tomato turquoise violet wheat white whitesmoke yellow yellowgreen".split(
    " ",
  ),
);

// Properties whose identifiers name things, not colors.
const namingProperties = new Set([
  "animation",
  "animation-name",
  "container",
  "container-name",
  "font-family",
  "grid-area",
  "grid-column",
  "grid-row",
  "grid-template-areas",
  "transition",
  "transition-property",
  "view-transition-name",
  "will-change",
]);

const colorFunctionCall =
  /(?<![\w-])(rgba?|hsla?|hwb|lab|lch|oklab|oklch|color)\([^()]*\)/gi;
const colorPatterns = [/^--mt-(color|material|state)-/];

// The spellings of an rgb() color as the generator writes it: space-separated channels and a
// decimal alpha.
function colorSpellings(call) {
  const match = call.match(
    /^rgba?\(\s*([\d.]+)[\s,]+([\d.]+)[\s,]+([\d.]+)\s*(?:[,/]\s*([\d.]+%?))?\s*\)$/i,
  );
  if (!match) return [call];
  const [, red, green, blue, alpha] = match;
  const opacity = alpha?.endsWith("%") ? Number.parseFloat(alpha) / 100 : alpha;
  return [
    call,
    opacity === undefined || Number(opacity) === 1
      ? `rgb(${red} ${green} ${blue})`
      : `rgb(${red} ${green} ${blue} / ${Number(opacity)})`,
  ];
}
const hexColor = /#[0-9a-f]{3,8}(?![\w-])/gi;

function checkColors({ property, value }, tokens) {
  const literal = withoutVariables(value);
  const findings = [];
  if (/(?<![\w-])color-mix\(/i.test(literal)) {
    findings.push(
      "color-mix() outside the generated tokens. Add a color token with a mix extension.",
    );
  }
  for (const [hex] of literal.matchAll(hexColor)) {
    findings.push(
      `literal color ${hex}.${suggestion(tokens, [/^--mt-color-/], [hex])}`,
    );
  }
  for (const [data] of value.matchAll(/(["'])data:[\s\S]*?\1/g)) {
    for (const [, hex] of data.matchAll(
      /(?:#|%23)([0-9a-f]{3,8})(?![0-9a-z])/gi,
    )) {
      findings.push(
        `literal color #${hex} in a data URL. Add a cssImages entry to packages/design-system/icons.json and use its var(--mt-image-*).`,
      );
    }
  }
  for (const [whole, name] of literal.matchAll(colorFunctionCall)) {
    const found = tokens.find(colorPatterns, colorSpellings(whole));
    findings.push(
      `literal color ${name}().${
        found.length
          ? ` Use ${found.map((token) => `var(${token})`).join(" or ")}.`
          : " Use a color, shadow, or material token."
      }`,
    );
  }
  if (!namingProperties.has(property)) {
    for (const word of literal.match(/(?<![\w-])[a-z]+(?![\w-])/gi) ?? []) {
      if (namedColors.has(word.toLowerCase())) {
        findings.push(`named color ${word}. Use a color token.`);
      }
    }
  }
  return findings;
}

// Motion

const motionProperties = new Set([
  "transition",
  "transition-duration",
  "transition-delay",
  "transition-timing-function",
  "animation",
  "animation-duration",
  "animation-delay",
  "animation-timing-function",
]);

const easingCurves = {
  ease: "cubic-bezier(0.25, 0.1, 0.25, 1)",
  "ease-in": "cubic-bezier(0.42, 0, 1, 1)",
  "ease-out": "cubic-bezier(0, 0, 0.58, 1)",
  "ease-in-out": "cubic-bezier(0.42, 0, 0.58, 1)",
  linear: "cubic-bezier(0, 0, 1, 1)",
};

function checkMotion({ value }, tokens) {
  const literal = withoutVariables(value);
  const findings = [];
  for (const [duration, number, unit] of literal.matchAll(
    /(?<![\w.-])((?:\d*\.)?\d+)(ms|s)(?![\w-])/g,
  )) {
    const ms = Number.parseFloat(number) * (unit === "s" ? 1000 : 1);
    if (ms === 0) continue;
    findings.push(
      `literal duration ${duration}.${suggestion(tokens, [/^--mt-motion-(?!easing-)/], [`${ms}ms`])}`,
    );
  }
  const easing = [/^--mt-motion-easing-/];
  for (const [curve, numbers] of literal.matchAll(/cubic-bezier\(([^)]*)\)/g)) {
    const spelled = `cubic-bezier(${numbers
      .split(",")
      .map((part) => Number(part.trim()))
      .join(", ")})`;
    findings.push(
      `literal easing ${curve}.${suggestion(tokens, easing, [spelled])}`,
    );
  }
  for (const [, keyword] of literal.matchAll(
    /(?<![\w-])(ease|ease-in|ease-out|ease-in-out|linear|step-start|step-end|steps)(?![\w-])/g,
  )) {
    const curve = easingCurves[keyword];
    findings.push(
      `literal easing ${keyword}.${curve ? suggestion(tokens, easing, [curve]) : ""}`,
    );
  }
  return findings;
}

// Lengths

// A negative length names the token with that exact value, such as an inset focus offset, or
// else the positive token negated.
function checkLengths(declaration, tokens, what, patterns) {
  return lengths(declaration.value).map((length) => {
    const exact = length.startsWith("-") ? tokens.find(patterns, [length]) : [];
    if (exact.length) {
      return `literal ${what} ${length}.${suggestion(tokens, patterns, [length])}`;
    }
    const found = tokens.find(patterns, spellings(length));
    const negated = length.startsWith("-") && found.length;
    return negated
      ? `literal ${what} ${length}. Use ${found.map((name) => `calc(var(${name}) * -1)`).join(" or ")}.`
      : `literal ${what} ${length}.${suggestion(tokens, patterns, spellings(length))}`;
  });
}

const spacing = {
  what: "spacing",
  patterns: [/^--mt-space-/, /^--mt-text-space-/],
};
const radius = { what: "radius", patterns: [/^--mt-radius-/] };
const stroke = {
  what: "stroke width",
  patterns: [/^--mt-size-stroke-/, /^--mt-state-focus-ring-width$/],
};
const focusOffset = {
  what: "focus ring offset",
  patterns: [/^--mt-state-focus-ring-offset/],
};
const shadow = {
  what: "shadow length",
  patterns: [/^--mt-size-stroke-/, /^--mt-state-focus-(ring|halo)-width$/],
};

function lengthRule(property) {
  if (
    /^(padding|margin|gap|row-gap|column-gap|scroll-margin|scroll-padding)(-|$)/.test(
      property,
    ) ||
    /^--[\w-]*(gap|padding|margin)$/.test(property)
  ) {
    return spacing;
  }
  if (/^border(-[a-z]+)*-radius$|^--[\w-]*radius$/.test(property))
    return radius;
  if (
    /^(border(-(top|right|bottom|left|block|inline)(-(start|end))?)?|outline|column-rule)(-width)?$/.test(
      property,
    )
  ) {
    return stroke;
  }
  if (property === "outline-offset") return focusOffset;
  if (property === "box-shadow") return shadow;
  return undefined;
}

// Values that must be a single token.

const tokenOnly = {
  "z-index": {
    allowed: ["auto"],
    what: "z-index",
    patterns: [/^--mt-layout-layer-/],
  },
  "backdrop-filter": {
    allowed: ["none"],
    what: "backdrop-filter",
    patterns: [/^--mt-material-[\w-]+-backdrop-filter$/],
  },
  "-webkit-backdrop-filter": {
    allowed: ["none"],
    what: "backdrop-filter",
    patterns: [/^--mt-material-[\w-]+-backdrop-filter$/],
  },
  opacity: {
    allowed: ["0", "1"],
    what: "opacity",
    patterns: [/^--mt-state-[\w-]+-opacity-/],
  },
};

function checkTokenOnly({ value }, rule, tokens) {
  const literal = withoutVariables(value).replace(/\s+/g, " ");
  if (!literal || rule.allowed.includes(literal)) return [];
  return [
    `literal ${rule.what} ${literal}.${suggestion(tokens, rule.patterns, [literal])}`,
  ];
}

function checkDeclaration(declaration, tokens) {
  const { property } = declaration;
  const findings = checkColors(declaration, tokens);
  if (property.startsWith("--") || motionProperties.has(property)) {
    findings.push(...checkMotion(declaration, tokens));
  }
  if (property.startsWith("--")) {
    const rule = lengthRule(property);
    if (rule)
      findings.push(
        ...checkLengths(declaration, tokens, rule.what, rule.patterns),
      );
    return findings;
  }
  if (typography[property])
    findings.push(...checkTypography(declaration, tokens));
  if (
    property === "font" &&
    withoutVariables(declaration.value) !== "inherit"
  ) {
    findings.push(
      "literal font shorthand. Set each property from a text role.",
    );
  }
  const only = tokenOnly[property];
  if (only) findings.push(...checkTokenOnly(declaration, only, tokens));
  const rule = lengthRule(property) ?? iconRule(declaration);
  if (rule)
    findings.push(
      ...checkLengths(declaration, tokens, rule.what, rule.patterns),
    );
  return findings;
}

// An icon's box is sized from the size.icon scale.
const icon = { what: "icon size", patterns: [/^--mt-size-icon-/] };

function iconRule({ property, selector }) {
  const sizesIcon =
    /^(width|height|inline-size|block-size|min-width|min-height)$/.test(
      property,
    ) &&
    selector
      .split(",")
      .some((part) => /(^|[\s>+~])svg(?![\w-])[^\s>+~]*$/.test(part.trim()));
  return sizesIcon ? icon : undefined;
}

// Queries

const queryFeature =
  /\(\s*(min-width|max-width|min-height|max-height|width|height)\s*(?::|[<>]=?)\s*([^)]+)\)/g;

// A media query width must be a layout breakpoint: max-width at the token value, min-width one
// pixel above it. CSS cannot read variables in media queries, so the literal must match.
function checkMediaQuery({ params }, tokens) {
  const findings = [];
  for (const [, feature, raw] of params.matchAll(queryFeature)) {
    const px = raw.trim().match(/^(\d+)px$/);
    const width = px && Number(px[1]) - (feature === "min-width" ? 1 : 0);
    const found =
      px && /^(min|max)-width$/.test(feature)
        ? tokens.find([/^--mt-layout-breakpoint-/], [`${width}px`])
        : [];
    if (found.length !== 1) {
      findings.push(
        `media query (${feature}: ${raw.trim()}) is not a layout breakpoint. Use max-width at a --mt-layout-breakpoint-* value or min-width one pixel above it, adding a layout.breakpoint token if none fits.`,
      );
    }
  }
  return findings;
}

// A container query width must equal a layout.container token.
function checkContainerQuery({ params }, tokens) {
  const findings = [];
  for (const [, feature, raw] of params.matchAll(queryFeature)) {
    const px = raw.trim().match(/^(\d+)px$/);
    if (
      !px ||
      !/width$/.test(feature) ||
      !tokens.find([/^--mt-layout-container-/], [`${px[1]}px`]).length
    ) {
      findings.push(
        `container query (${feature}: ${raw.trim()}) is not a --mt-layout-container-* value.`,
      );
    }
  }
  return findings;
}

// Entry points

export function checkCss(file, css, tokens) {
  const { declarations, atRules } = parseCss(css);
  const findings = [];
  const report = (line, messages) => {
    for (const message of messages) findings.push({ file, line, message });
  };
  const local = new Set(
    declarations
      .map((declaration) => declaration.property)
      .filter((property) => property.startsWith("--mt-")),
  );
  for (const declaration of declarations) {
    for (const [, name, fallback] of declaration.value.matchAll(
      /var\((--mt-[\w-]+)\s*(,)?/g,
    )) {
      if (!tokens.names.has(name) && !local.has(name)) {
        report(declaration.line, [`undefined token ${name}.`]);
      } else if (fallback) {
        // A fallback would hide a literal from these rules, and tokens are always defined.
        report(declaration.line, [`token ${name} has a fallback. Remove it.`]);
      }
    }
    report(declaration.line, checkDeclaration(declaration, tokens));
  }
  for (const atRule of atRules) {
    if (atRule.name === "media")
      report(atRule.line, checkMediaQuery(atRule, tokens));
    if (atRule.name === "container") {
      report(atRule.line, checkContainerQuery(atRule, tokens));
    }
  }
  return findings;
}

// Scripts may not spell colors or curves either. Server-rendered images read themeColors from
// the generated design-system module, and `allowed` lists colors a script must keep, such as
// another company's brand mark.
export function checkScript(file, code, tokens, allowed = []) {
  const findings = [];
  code.split("\n").forEach((text, index) => {
    const report = (message) =>
      findings.push({ file, line: index + 1, message });
    for (const [, hex] of text.matchAll(/["'`]\s*(#[0-9a-f]{3,8})\s*["'`]/gi)) {
      if (allowed.includes(hex.toUpperCase())) continue;
      report(
        `literal color ${hex}.${suggestion(tokens, [/^--mt-color-/], [hex])}`,
      );
    }
    if (/(?<![\w-])(rgba?|hsla?)\(\s*\d/.test(text))
      report("literal color function.");
    if (/(?<![\w-])color-mix\(/.test(text)) {
      report("color-mix() outside the generated tokens.");
    }
    if (/(?<![\w-])cubic-bezier\(/.test(text))
      report("literal easing cubic-bezier().");
  });
  return findings;
}
