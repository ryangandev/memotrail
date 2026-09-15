import { describe, expect, it } from "vitest";
import {
  createEntryRichText,
  entryRichTextFromMetadata,
  metadataWithEntryRichText,
  parseEntryRichTextJson,
  plainTextDocument,
  plainTextFromDocument,
  type RichTextDocument,
} from "./rich-text";

describe("Entry rich text", () => {
  it("keeps plaintext as the canonical searchable body", () => {
    const document: RichTextDocument = {
      type: "doc",
      content: [
        {
          type: "paragraph",
          content: [
            { type: "text", text: "A " },
            { type: "text", text: "bold", marks: [{ type: "bold" }] },
            {
              type: "text",
              text: " memory",
              marks: [
                {
                  type: "link",
                  attrs: {
                    href: "https://example.com/memory",
                    title: null,
                  },
                },
              ],
            },
          ],
        },
        {
          type: "bulletList",
          content: [
            {
              type: "listItem",
              content: [
                {
                  type: "paragraph",
                  content: [{ type: "text", text: "First detail" }],
                },
              ],
            },
          ],
        },
      ],
    };

    const value = createEntryRichText(document);
    expect(value?.text).toBe("A bold memory\nFirst detail");
    expect(
      entryRichTextFromMetadata(metadataWithEntryRichText(value), value!.text),
    ).toEqual(value);
  });

  it("round trips plain text without treating it as HTML", () => {
    const text = "<strong>Still text</strong>\n\nSecond thought";
    const document = plainTextDocument(text);

    expect(plainTextFromDocument(document)).toBe(text);
    expect(createEntryRichText(document)?.text).toBe(text);
  });

  it("ignores stale formatting when another client changes the body", () => {
    const value = createEntryRichText(plainTextDocument("Original"));

    expect(
      entryRichTextFromMetadata(metadataWithEntryRichText(value), "Changed"),
    ).toBeNull();
  });

  it("rejects unsafe links and unsupported document shapes", () => {
    const unsafe = {
      version: 1,
      text: "Open",
      document: {
        type: "doc",
        content: [
          {
            type: "paragraph",
            content: [
              {
                type: "text",
                text: "Open",
                marks: [
                  { type: "link", attrs: { href: "javascript:alert(1)" } },
                ],
              },
            ],
          },
        ],
      },
    };

    expect(entryRichTextFromMetadata({ body_rich: unsafe }, "Open")).toBeNull();
    expect(
      entryRichTextFromMetadata(
        {
          body_rich: {
            ...unsafe,
            document: { type: "doc", content: [{ type: "image" }] },
          },
        },
        "Open",
      ),
    ).toBeNull();
  });

  it("round-trips validated formatting across the server action boundary", () => {
    const value = createEntryRichText({
      type: "doc",
      content: [
        {
          type: "paragraph",
          content: [
            {
              type: "text",
              marks: [
                {
                  type: "link",
                  attrs: { href: "https://example.com/memory" },
                },
                { type: "bold" },
              ],
              text: "A thought worth keeping.",
            },
          ],
        },
      ],
    });

    expect(value).not.toBeNull();
    expect(
      parseEntryRichTextJson(JSON.stringify(value), value!.text),
    ).toEqual(value);
    expect(
      parseEntryRichTextJson(JSON.stringify(value), "A different body."),
    ).toBeNull();
  });
});
