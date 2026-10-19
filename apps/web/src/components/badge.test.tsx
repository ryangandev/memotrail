import { readFileSync } from "node:fs";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { badgeSizes, badgeTones } from "@/generated/design-system";
import { Badge } from "./badge";

const css = readFileSync(
  new URL("./badge.module.css", import.meta.url),
  "utf8",
);

describe("Badge", () => {
  it("renders the spec's defaults: small, accent, and sentence case", () => {
    const html = renderToStaticMarkup(<Badge>Draft</Badge>);

    expect(html).toContain('data-size="small"');
    expect(html).toContain('data-tone="accent"');
    expect(html).not.toContain("data-uppercase");
    expect(html).toContain("data-ui-badge");
  });

  it("marks uppercase only when it is on", () => {
    const html = renderToStaticMarkup(<Badge uppercase>New</Badge>);

    expect(html).toContain('data-uppercase="true"');
  });

  // The spec's value lists type the props, so TypeScript rejects a value the spec drops. These
  // catch the other direction: a value the spec adds but the stylesheet never draws.
  it.each(badgeTones)("styles the %s tone", (tone) => {
    expect(css).toContain(`.badge[data-tone="${tone}"]`);
  });

  it.each(badgeSizes)("styles the %s size and its uppercase role", (size) => {
    const role = `--mt-type-badge-${size}`;
    expect(css).toContain(`.badge[data-size="${size}"] {`);
    expect(css).toContain(`font-size: var(${role}-font-size);`);
    expect(css).toContain(
      `.badge[data-size="${size}"][data-uppercase="true"] {`,
    );
    expect(css).toContain(`font-size: var(${role}-caps-font-size);`);
  });
});
