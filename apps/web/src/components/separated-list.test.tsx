import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { SeparatedList } from "./separated-list";

const text = (html: string) => html.replace(/<[^>]+>/g, "");

describe("SeparatedList", () => {
  it("hides one separator from assistive technology before each later fact", () => {
    const html = renderToStaticMarkup(
      <SeparatedList aria-label="Summary">
        <span>8 tracks</span>
        {null}
        {false}
        <span>1 moment</span>
        <a href="/timeline">2017 to 2026</a>
      </SeparatedList>,
    );

    expect(html).toContain('aria-label="Summary"');
    expect(html).toContain('data-align="start"');
    expect(html.match(/<span aria-hidden="true"[^>]*>·<\/span>/g)).toHaveLength(
      2,
    );
    expect(text(html)).toBe("8 tracks·1 moment·2017 to 2026");
  });

  it("puts each separator after its fact when lines align to the end", () => {
    const html = renderToStaticMarkup(
      <SeparatedList align="end">
        <span>Powered by Geoapify</span>
        <span>© OpenStreetMap contributors</span>
      </SeparatedList>,
    );

    expect(html).toContain('data-align="end"');
    expect(html.match(/aria-hidden="true"/g)).toHaveLength(1);
    expect(text(html)).toBe("Powered by Geoapify·© OpenStreetMap contributors");
  });

  it("uses only phrasing elements and no separator for a single fact", () => {
    const html = renderToStaticMarkup(
      <SeparatedList spacing="word">
        <span>0 Entries</span>
      </SeparatedList>,
    );

    expect(html).toContain('data-spacing="word"');
    expect(html).not.toMatch(/<(?!\/?span\b)/);
    expect(text(html)).toBe("0 Entries");
  });
});
