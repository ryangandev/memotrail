import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { Checkbox } from "./checkbox";

describe("Checkbox", () => {
  it("renders a native checkbox named by its label and described by its explanation", () => {
    const html = renderToStaticMarkup(
      <Checkbox description="Still going on" id="present" label="Present" />,
    );

    expect(html).toContain('type="checkbox"');
    expect(html).toContain('for="present"');
    expect(html).toContain('aria-labelledby="present-label"');
    expect(html).toContain('aria-describedby="present-description"');
    expect(html).toMatch(/id="present-label">Present</);
    expect(html).toMatch(/id="present-description">Still going on</);
  });

  it("omits the description reference when there is no description", () => {
    const html = renderToStaticMarkup(<Checkbox id="plain" label="Plain" />);

    expect(html).not.toContain("aria-describedby");
    expect(html).not.toContain("plain-description");
  });

  it("keeps a caller's description reference beside its own", () => {
    const html = renderToStaticMarkup(
      <Checkbox
        aria-describedby="elsewhere"
        description="Explained"
        id="both"
        label="Both"
      />,
    );

    expect(html).toContain('aria-describedby="elsewhere both-description"');
  });

  it("passes form and state props to the input", () => {
    const html = renderToStaticMarkup(
      <Checkbox
        defaultChecked
        disabled
        label="Include photos"
        name="photos"
        required
        value="yes"
      />,
    );
    const input = html.match(/<input[^>]*>/)![0];

    expect(input).toContain('name="photos"');
    expect(input).toContain('value="yes"');
    expect(input).toContain('checked=""');
    expect(input).toContain('disabled=""');
    expect(input).toContain('required=""');
  });

  it("hides the drawn box from assistive technology and records its size", () => {
    const html = renderToStaticMarkup(<Checkbox label="Small" size="small" />);

    expect(html).toContain('data-size="small"');
    expect(html).toContain('data-ui-checkbox="true"');
    expect(html).toMatch(/<span aria-hidden="true" class="[^"]*"><svg/);
  });
});
