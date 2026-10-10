import { readFileSync } from "node:fs";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { buttonSizes, buttonVariants } from "@/generated/design-system";
import { Button, ButtonLink } from "./button";

const css = readFileSync(
  new URL("./button.module.css", import.meta.url),
  "utf8",
);

describe("Button", () => {
  it("renders the spec's defaults: a medium primary button", () => {
    const html = renderToStaticMarkup(<Button>Save</Button>);

    expect(html).toContain('type="button"');
    expect(html).toContain('data-variant="primary"');
    expect(html).toContain('data-size="medium"');
    expect(html).not.toContain("aria-busy");
    expect(html).not.toContain("disabled");
  });

  it("disables a loading button and marks it busy", () => {
    const html = renderToStaticMarkup(<Button loading>Saving</Button>);

    expect(html).toContain('aria-busy="true"');
    expect(html).toContain('disabled=""');
    expect(html).toMatch(
      /<span aria-hidden="true" class="[^"]*"><\/span>Saving/,
    );
  });

  it("keeps ButtonLink an anchor with the same defaults", () => {
    const html = renderToStaticMarkup(
      <ButtonLink href="/library">Back to Library</ButtonLink>,
    );

    expect(html).toMatch(/^<a /);
    expect(html).toContain('href="/library"');
    expect(html).toContain('data-variant="primary"');
    expect(html).toContain('data-size="medium"');
  });

  // The spec's value lists type the props, so TypeScript rejects a value the spec drops. These
  // catch the other direction: a value the spec adds but the stylesheet never draws.
  it.each(buttonVariants)("styles the %s variant and its hover", (variant) => {
    expect(css).toContain(`.button[data-variant="${variant}"] {`);
    expect(css).toContain(
      `.button[data-variant="${variant}"]:not(:disabled):hover {`,
    );
  });

  it.each(buttonSizes)("sizes %s controls from the control token", (size) => {
    expect(css).toContain(`min-height: var(--mt-size-control-${size});`);
  });
});
