import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { EntryRichTextContent } from "./entry-rich-text-content";

describe("EntryRichTextContent", () => {
  it("renders validated formatting without using HTML from storage", () => {
    const html = renderToStaticMarkup(
      <EntryRichTextContent
        body={"Remember this\nOne item"}
        richText={{
          document: {
            content: [
              {
                content: [
                  {
                    marks: [{ type: "bold" }],
                    text: "Remember this",
                    type: "text",
                  },
                ],
                type: "paragraph",
              },
              {
                content: [
                  {
                    content: [
                      {
                        content: [{ text: "One item", type: "text" }],
                        type: "paragraph",
                      },
                    ],
                    type: "listItem",
                  },
                ],
                type: "bulletList",
              },
            ],
            type: "doc",
          },
          text: "Remember this\nOne item",
          version: 1,
        }}
      />,
    );

    expect(html).toContain("<strong>Remember this</strong>");
    expect(html).toContain("<ul><li><p>One item</p></li></ul>");
    expect(html).not.toContain("dangerouslySetInnerHTML");
  });

  it("falls back to plaintext when metadata does not match the body", () => {
    const html = renderToStaticMarkup(
      <EntryRichTextContent
        body="Current body"
        metadata={{
          body_rich: {
            document: {
              content: [
                {
                  content: [{ text: "Old body", type: "text" }],
                  type: "paragraph",
                },
              ],
              type: "doc",
            },
            text: "Old body",
            version: 1,
          },
        }}
      />,
    );

    expect(html).toContain("<p>Current body</p>");
    expect(html).not.toContain("Old body");
  });
});
