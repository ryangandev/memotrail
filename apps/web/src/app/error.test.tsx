import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import GlobalError from "./global-error";
import RouteError from "./error";
import NotFound from "./not-found";

const error = Object.assign(new Error("Failed to fetch"), { digest: "d1" });

describe("Route boundaries", () => {
  it("offers a retry and a way home instead of the framework's crash page", () => {
    const html = renderToStaticMarkup(
      <RouteError error={error} retry={() => undefined} />,
    );

    expect(html).toContain("This page could not load");
    expect(html).toContain("Try again");
    expect(html).toContain('href="/"');
    expect(html).not.toContain("Failed to fetch");
  });

  it("explains a missing page and points to Home and Library", () => {
    const html = renderToStaticMarkup(<NotFound />);

    expect(html).toContain("Page not found");
    expect(html).toContain('href="/"');
    expect(html).toContain('href="/library"');
  });

  it("brings its own document when the root layout fails", () => {
    const html = renderToStaticMarkup(
      <GlobalError error={error} retry={() => undefined} />,
    );

    expect(html).toMatch(/^<html lang="en"/);
    expect(html).toContain("MemoTrail could not load");
    expect(html).toContain("Try again");
    expect(html).not.toContain("Failed to fetch");
  });
});
