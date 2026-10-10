import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { SectionHeader } from "./section-header";

describe("SectionHeader", () => {
  it("renders a section heading at level 2 by default", () => {
    const html = renderToStaticMarkup(<SectionHeader title="Recent Entries" />);

    expect(html).toContain('data-variant="section"');
    expect(html).toMatch(/<h2 class="[^"]*">Recent Entries<\/h2>/);
    expect(html).not.toContain("<p");
  });

  it("lets the caller choose the heading level and id", () => {
    const html = renderToStaticMarkup(
      <SectionHeader
        headingId="results-heading"
        headingLevel={3}
        title="Results"
      />,
    );

    expect(html).toMatch(
      /<h3 class="[^"]*" id="results-heading">Results<\/h3>/,
    );
  });

  it("renders the list variant with detail beside the title and an action", () => {
    const html = renderToStaticMarkup(
      <SectionHeader
        action={<a href="/library">Show all</a>}
        detail="12 items"
        title="All items"
        variant="list"
      />,
    );

    expect(html).toContain('data-variant="list"');
    expect(html.indexOf("All items")).toBeLessThan(html.indexOf("12 items"));
    expect(html.indexOf("12 items")).toBeLessThan(html.indexOf("Show all"));
    expect(html).toContain('<a href="/library">Show all</a>');
  });

  it("moves detail to the trailing group before the action when aligned to the end", () => {
    const html = renderToStaticMarkup(
      <SectionHeader
        action={<a href="/library">Show all</a>}
        detail="12 items"
        detailAlign="end"
        title="All items"
        variant="list"
      />,
    );
    const trailing = html.slice(html.indexOf("</h2>"));

    expect(trailing).toContain("12 items");
    expect(trailing.indexOf("12 items")).toBeLessThan(
      trailing.indexOf("Show all"),
    );
  });

  it("renders a description as a paragraph and marks the header stacked", () => {
    const html = renderToStaticMarkup(
      <SectionHeader description="Your identity" title="Account" />,
    );

    expect(html).toContain('data-stacked="true"');
    expect(html).toMatch(/<p class="[^"]*">Your identity<\/p>/);
  });

  it("passes layout props to the wrapper", () => {
    const html = renderToStaticMarkup(
      <SectionHeader className="placed" id="wrapper" title="Placed" />,
    );

    expect(html).toContain('id="wrapper"');
    expect(html).toMatch(/class="[^"]*placed[^"]*"/);
  });
});
