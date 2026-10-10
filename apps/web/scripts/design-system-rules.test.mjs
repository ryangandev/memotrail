import { describe, expect, test } from "vitest";
import {
  checkCss,
  checkScript,
  parseCss,
  readTokens,
} from "./design-system-rules.mjs";

const tokens = readTokens(`
:root {
  --mt-font-size-fine: 10px;
  --mt-font-weight-semibold: 600;
  --mt-line-height-none: 1;
  --mt-type-eyebrow-font-size: var(--mt-font-size-fine);
  --mt-type-eyebrow-letter-spacing: 0.1em;
  --mt-space-1: 4px;
  --mt-space-1-5: 6px;
  --mt-text-space-list-indent: 1.5em;
  --mt-radius-small: 8px;
  --mt-size-stroke-thin: 1px;
  --mt-state-focus-ring-offset: 3px;
  --mt-state-focus-ring-offset-inset: -2px;
  --mt-size-icon-18: 18px;
  --mt-color-brand-ring: #315E4F;
  --mt-color-menu-scrim: rgb(0 0 0 / 0.48);
  --mt-layout-breakpoint-720: 720px;
  --mt-layout-container-620: 620px;
  --mt-layout-layer-dialog: 70;
  --mt-motion-quick: 120ms;
  --mt-motion-easing-enter: cubic-bezier(0, 0, 0.58, 1);
  --mt-material-chip-backdrop-filter: blur(8px);
  --mt-state-disabled-opacity-button: 0.5;
}
:root, [data-theme="light"] {
  --mt-color-accent: #315E4F;
}
[data-theme="dark"] {
  --mt-color-accent: #82AD98;
}
`);

const messages = (css) =>
  checkCss("example.module.css", css, tokens).map(
    ({ line, message }) => `${line}: ${message}`,
  );

describe("parseCss", () => {
  test("reads declarations with their lines and ignores comments and strings", () => {
    const { declarations, atRules } = parseCss(`/* a; b: c; */
.a {
  content: "x; y: z";
  color: var(--mt-color-accent);
}
@media (max-width: 720px) {
  .a { gap: 4px; }
}`);
    expect(declarations).toEqual([
      expect.objectContaining({ property: "content", line: 3 }),
      expect.objectContaining({ property: "color", line: 4 }),
      expect.objectContaining({ property: "gap", value: "4px", line: 7 }),
    ]);
    expect(atRules).toEqual([
      expect.objectContaining({
        name: "media",
        params: "(max-width: 720px)",
        line: 6,
      }),
    ]);
  });
});

describe("checkCss", () => {
  test("accepts token references and neutral keywords", () => {
    expect(
      messages(`.a {
  font-size: var(--mt-type-eyebrow-font-size);
  letter-spacing: 0;
  line-height: inherit;
  margin: 0 auto;
  padding: calc(var(--mt-space-1) * -1) 50%;
  border: var(--mt-size-stroke-thin) solid transparent;
  color: currentColor;
  z-index: auto;
  opacity: 0;
  transition: opacity var(--mt-motion-quick) var(--mt-motion-easing-enter);
  background: linear-gradient(var(--mt-color-accent), transparent);
}`),
    ).toEqual([]);
  });

  test("names the token for a literal text value", () => {
    expect(
      messages(`.a {
  font-size: 10px;
  font-weight: 600;
  line-height: 1;
  letter-spacing: 0.1em;
  font-family: Georgia;
}`),
    ).toEqual([
      "2: literal font-size 10px. Use var(--mt-font-size-fine) or var(--mt-type-eyebrow-font-size).",
      "3: literal font-weight 600. Use var(--mt-font-weight-semibold).",
      "4: literal line-height 1. Use var(--mt-line-height-none).",
      "5: literal letter-spacing 0.1em. Use var(--mt-type-eyebrow-letter-spacing).",
      "6: literal font-family Georgia.",
    ]);
  });

  test("rejects every literal color form, including in custom properties", () => {
    expect(
      messages(`.a {
  color: #315e4f;
  background: rgb(0 0 0 / 48%);
  border-color: white;
  --tint: color-mix(in srgb, var(--mt-color-accent) 10%, transparent);
  outline-color: rgb(1 2 3);
  background-image: url("data:image/svg+xml,%3Cpath stroke='%23716D63'/%3E");
}`),
    ).toEqual([
      "2: literal color #315e4f. Use var(--mt-color-brand-ring).",
      "3: literal color rgb(). Use var(--mt-color-menu-scrim).",
      "4: named color white. Use a color token.",
      "5: color-mix() outside the generated tokens. Add a color token with a mix extension.",
      "6: literal color rgb(). Use a color, shadow, or material token.",
      "7: literal color #716D63 in a data URL. Add a cssImages entry to packages/design-system/icons.json and use its var(--mt-image-*).",
    ]);
  });

  test("only names a token that renders the literal in every theme", () => {
    expect(messages(".a { color: #82AD98; }")).toEqual([
      "1: literal color #82AD98.",
    ]);
  });

  test("rejects literal motion, layers, materials, and opacity", () => {
    expect(
      messages(`.a {
  transition: opacity 120ms ease-out;
  animation: spin 0.8s cubic-bezier(0, 0, 0.58, 1) infinite;
  --motion: 120ms linear;
  z-index: 70 !important;
  backdrop-filter: blur(8px);
  opacity: 0.5;
}`),
    ).toEqual([
      "2: literal duration 120ms. Use var(--mt-motion-quick).",
      "2: literal easing ease-out. Use var(--mt-motion-easing-enter).",
      "3: literal duration 0.8s.",
      "3: literal easing cubic-bezier(0, 0, 0.58, 1). Use var(--mt-motion-easing-enter).",
      "4: literal duration 120ms. Use var(--mt-motion-quick).",
      "4: literal easing linear.",
      "5: literal z-index 70. Use var(--mt-layout-layer-dialog).",
      "6: literal backdrop-filter blur(8px). Use var(--mt-material-chip-backdrop-filter).",
      "7: literal opacity 0.5. Use var(--mt-state-disabled-opacity-button).",
    ]);
  });

  test("rejects literal spacing, radius, strokes, focus offsets, and shadow lengths", () => {
    expect(
      messages(`.a {
  padding: 6px 1.5em;
  --list-gap: 4px;
  border-radius: 8px;
  border-bottom: 1px solid var(--mt-color-accent);
  outline-offset: 3px;
  box-shadow: 0 0 0 1px var(--mt-color-accent);
}`),
    ).toEqual([
      "2: literal spacing 6px. Use var(--mt-space-1-5).",
      "2: literal spacing 1.5em. Use var(--mt-text-space-list-indent).",
      "3: literal spacing 4px. Use var(--mt-space-1).",
      "4: literal radius 8px. Use var(--mt-radius-small).",
      "5: literal stroke width 1px. Use var(--mt-size-stroke-thin).",
      "6: literal focus ring offset 3px. Use var(--mt-state-focus-ring-offset).",
      "7: literal shadow length 1px. Use var(--mt-size-stroke-thin).",
    ]);
  });

  test("names an exact negative token, or else negates the positive one", () => {
    expect(
      messages(`.a {
  outline-offset: -2px;
  margin-left: -4px;
}`),
    ).toEqual([
      "2: literal focus ring offset -2px. Use var(--mt-state-focus-ring-offset-inset).",
      "3: literal spacing -4px. Use calc(var(--mt-space-1) * -1).",
    ]);
  });

  test("sizes icons from the size.icon scale", () => {
    expect(
      messages(`.a > svg {
  width: 18px;
}
.a {
  width: 18px;
}`),
    ).toEqual(["2: literal icon size 18px. Use var(--mt-size-icon-18)."]);
  });

  test("requires media and container queries to use layout tokens", () => {
    expect(
      messages(`@media (max-width: 720px) {}
@media (min-width: 721px) {}
@media (prefers-reduced-motion: reduce) {}
@media (max-width: 700px) {}
@media (min-height: 400px) {}
@container (min-width: 620px) {}
@container (max-width: 600px) {}`),
    ).toEqual([
      "4: media query (max-width: 700px) is not a layout breakpoint. Use max-width at a --mt-layout-breakpoint-* value or min-width one pixel above it, adding a layout.breakpoint token if none fits.",
      "5: media query (min-height: 400px) is not a layout breakpoint. Use max-width at a --mt-layout-breakpoint-* value or min-width one pixel above it, adding a layout.breakpoint token if none fits.",
      "7: container query (max-width: 600px) is not a --mt-layout-container-* value.",
    ]);
  });

  test("reports tokens the generated stylesheet does not define", () => {
    expect(messages(".a { gap: var(--mt-space-99); }")).toEqual([
      "1: undefined token --mt-space-99.",
    ]);
  });

  test("rejects a fallback on a token, which would hide a literal", () => {
    expect(messages(".a { gap: var(--mt-space-1, 4px); }")).toEqual([
      "1: token --mt-space-1 has a fallback. Remove it.",
    ]);
  });
});

describe("checkScript", () => {
  test("rejects literal colors and curves unless the file must keep them", () => {
    const code = `const a = "#315E4F";
const b = \`rgb(0 0 0)\`;
const c = "cubic-bezier(0, 0, 1, 1)";
const d = "#4285F4";
const anchor = "#main";`;
    expect(
      checkScript("example.tsx", code, tokens, ["#4285F4"]).map(
        ({ line, message }) => `${line}: ${message}`,
      ),
    ).toEqual([
      "1: literal color #315E4F. Use var(--mt-color-brand-ring).",
      "2: literal color function.",
      "3: literal easing cubic-bezier().",
    ]);
  });
});
