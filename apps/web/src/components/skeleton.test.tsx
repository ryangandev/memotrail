import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { Skeleton } from "./skeleton";

describe("Skeleton", () => {
  it("is decorative and hidden from assistive technology", () => {
    const html = renderToStaticMarkup(<Skeleton />);

    expect(html).toContain('aria-hidden="true"');
    expect(html).not.toContain("role=");
    expect(html).toContain("data-ui-skeleton");
  });

  it("defaults to an animated block and records its shape", () => {
    const block = renderToStaticMarkup(<Skeleton />);

    expect(block).toContain('data-animated="true"');
    expect(block).toContain('data-shape="block"');
    for (const shape of ["fill", "line", "circle"] as const) {
      expect(renderToStaticMarkup(<Skeleton shape={shape} />)).toContain(
        `data-shape="${shape}"`,
      );
    }
  });

  it("can stop its shimmer", () => {
    expect(renderToStaticMarkup(<Skeleton animated={false} />)).toContain(
      'data-animated="false"',
    );
  });

  it("sizes itself from width and height without dropping a caller's style", () => {
    const html = renderToStaticMarkup(
      <Skeleton
        height="42px"
        style={{ marginTop: 12 }}
        width="min(68%, 460px)"
      />,
    );

    expect(html).toContain("width:min(68%, 460px)");
    expect(html).toContain("height:42px");
    expect(html).toContain("margin-top:12px");
  });
});
