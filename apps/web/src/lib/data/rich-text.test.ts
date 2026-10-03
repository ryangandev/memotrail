import { getSchema } from "@tiptap/react";
import StarterKit from "@tiptap/starter-kit";
import { describe, expect, it } from "vitest";
import {
  createEntryRichText,
  entryRichTextFromMetadata,
  isEntryRichText,
  metadataWithEntryRichText,
  parseEntryRichTextJson,
  plainTextDocument,
  plainTextFromDocument,
  trimEntryNote,
  type EntryRichText,
  type RichTextDocument,
  type RichTextMark,
  type RichTextNode,
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
    expect(parseEntryRichTextJson(JSON.stringify(value), value!.text)).toEqual(
      value,
    );
    expect(
      parseEntryRichTextJson(JSON.stringify(value), "A different body."),
    ).toBeNull();
  });
});

describe("trimEntryNote", () => {
  // The editor's schema, so trimmed documents are checked as the editor will load them.
  const editorSchema = getSchema([
    StarterKit.configure({ heading: false, horizontalRule: false }),
  ]);
  const bold = { type: "bold" };
  const italic = { type: "italic" };
  const link = { attrs: { href: "https://example.com/" }, type: "link" };
  const text = (value: string, ...marks: RichTextMark[]): RichTextNode => ({
    ...(marks.length > 0 ? { marks } : {}),
    text: value,
    type: "text",
  });
  const hardBreak: RichTextNode = { type: "hardBreak" };
  const paragraph = (...content: RichTextNode[]): RichTextNode => ({
    ...(content.length > 0 ? { content } : {}),
    type: "paragraph",
  });
  const listItem = (...content: RichTextNode[]): RichTextNode => ({
    content,
    type: "listItem",
  });
  const bulletList = (...content: RichTextNode[]): RichTextNode => ({
    content,
    type: "bulletList",
  });
  const doc = (...content: RichTextNode[]): RichTextDocument => ({
    content,
    type: "doc",
  });
  const editorValue = (document: RichTextDocument) => {
    const value = createEntryRichText(document);
    expect(value).not.toBeNull();
    return value!;
  };
  const expectEditorDocument = (value: EntryRichText | null) => {
    expect(value).not.toBeNull();
    expect(() =>
      editorSchema.nodeFromJSON(value!.document).check(),
    ).not.toThrow();
  };

  it("drops the empty paragraph a trailing Enter leaves and keeps the formatting", () => {
    const value = editorValue(
      doc(paragraph(text("Bold capture", bold)), paragraph()),
    );
    expect(value.text).toBe("Bold capture\n");

    expect(trimEntryNote(value.text, value)).toEqual({
      body: "Bold capture",
      bodyRich: {
        document: doc(paragraph(text("Bold capture", bold))),
        text: "Bold capture",
        version: 1,
      },
    });
  });

  it("trims spaces inside the first and last text without losing their marks", () => {
    const value = editorValue(
      doc(
        paragraph(text("  Leading", italic), text(" middle ")),
        paragraph(text("trailing  ", link)),
      ),
    );

    expect(trimEntryNote(value.text, value)).toEqual({
      body: "Leading middle \ntrailing",
      bodyRich: {
        document: doc(
          paragraph(text("Leading", italic), text(" middle ")),
          paragraph(text("trailing", link)),
        ),
        text: "Leading middle \ntrailing",
        version: 1,
      },
    });
  });

  it("drops whitespace-only paragraphs and hard breaks at both edges", () => {
    const value = editorValue(
      doc(
        paragraph(text(" \t")),
        paragraph(hardBreak, text(" 　", bold)),
        paragraph(hardBreak, text(" Kept", bold), hardBreak),
        paragraph(text("  ", italic)),
        paragraph(),
      ),
    );

    expect(trimEntryNote(value.text, value)).toEqual({
      body: "Kept",
      bodyRich: {
        document: doc(paragraph(text("Kept", bold))),
        text: "Kept",
        version: 1,
      },
    });
  });

  it("keeps blank lines and spacing inside the note", () => {
    const document = doc(
      paragraph(text("First", bold)),
      paragraph(),
      paragraph(text("   ")),
      paragraph(text("Second"), hardBreak, hardBreak, text("third", italic)),
    );
    const value = editorValue(
      doc(paragraph(), ...document.content, paragraph()),
    );

    expect(trimEntryNote(value.text, value)).toEqual({
      body: "First\n\n   \nSecond\n\nthird",
      bodyRich: {
        document,
        text: "First\n\n   \nSecond\n\nthird",
        version: 1,
      },
    });
  });

  it("returns an already trimmed note unchanged", () => {
    const value = editorValue(
      doc(paragraph(text("Already ", bold), text("clean", link))),
    );

    expect(trimEntryNote(value.text, value)).toEqual({
      body: value.text,
      bodyRich: value,
    });
  });

  it("saves no formatting for a note that is only whitespace", () => {
    for (const document of [
      doc(paragraph()),
      doc(paragraph(text("   ", bold)), paragraph(hardBreak), paragraph()),
      doc(bulletList(listItem(paragraph()), listItem(paragraph(text(" "))))),
    ]) {
      const value = editorValue(document);
      expect(trimEntryNote(value.text, value)).toEqual({
        body: "",
        bodyRich: null,
      });
    }
  });

  it("trims blank blocks inside quotes, lists, and code at the edges", () => {
    const value = editorValue(
      doc(
        {
          content: [paragraph(), paragraph(text(" Quoted", italic))],
          type: "blockquote",
        },
        paragraph(text("Between")),
        bulletList(
          listItem(
            paragraph(text("Item ", bold)),
            bulletList(listItem(paragraph())),
          ),
          listItem(paragraph(text("  "))),
        ),
        { content: [text("\n  code();\n\n")], type: "codeBlock" },
        { content: [paragraph()], type: "blockquote" },
      ),
    );
    const body = "Quoted\nBetween\nItem \n\n  \n\n  code();";

    const trimmed = trimEntryNote(value.text, value);
    expect(trimmed).toEqual({
      body,
      bodyRich: {
        document: doc(
          { content: [paragraph(text("Quoted", italic))], type: "blockquote" },
          paragraph(text("Between")),
          bulletList(
            listItem(
              paragraph(text("Item ", bold)),
              bulletList(listItem(paragraph())),
            ),
            listItem(paragraph(text("  "))),
          ),
          { content: [text("\n  code();")], type: "codeBlock" },
        ),
        text: body,
        version: 1,
      },
    });
    expectEditorDocument(trimmed.bodyRich);
  });

  it("lifts nested items out of a blank leading list item so the editor can load them", () => {
    const value = editorValue(
      doc(
        bulletList(
          listItem(
            paragraph(text(" ")),
            bulletList(
              listItem(paragraph(text("Nested", bold))),
              listItem(paragraph(text("Sibling"))),
            ),
          ),
          listItem(paragraph(text("Outer"))),
        ),
      ),
    );

    const trimmed = trimEntryNote(value.text, value);
    expect(trimmed).toEqual({
      body: "Nested\nSibling\nOuter",
      bodyRich: {
        document: doc(
          bulletList(
            listItem(paragraph(text("Nested", bold))),
            listItem(paragraph(text("Sibling"))),
          ),
          bulletList(listItem(paragraph(text("Outer")))),
        ),
        text: "Nested\nSibling\nOuter",
        version: 1,
      },
    });
    expectEditorDocument(trimmed.bodyRich);
  });

  it("trims plain notes and drops formatting that describes other text", () => {
    const value = editorValue(doc(paragraph(text("Original", bold))));

    expect(trimEntryNote("  Plain note\n", null)).toEqual({
      body: "Plain note",
      bodyRich: null,
    });
    expect(trimEntryNote("Changed by voice ", value)).toEqual({
      body: "Changed by voice",
      bodyRich: null,
    });
  });

  it("always matches String.prototype.trim with a document the editor can load", () => {
    let seed = 27;
    const random = () => {
      seed = (seed + 0x6d2b79f5) | 0;
      let value = Math.imul(seed ^ (seed >>> 15), 1 | seed);
      value ^= value + Math.imul(value ^ (value >>> 7), 61 | value);
      return ((value ^ (value >>> 14)) >>> 0) / 4294967296;
    };
    const pick = <T>(values: readonly T[]) =>
      values[Math.floor(random() * values.length)];
    const count = (maximum: number) => Math.floor(random() * maximum);
    const words = [" ", "  ", "\t", " ", "　", "a", "b c", " d ", "e "];
    const marks: RichTextMark[][] = [[], [], [bold], [italic], [link]];
    const inline = (): RichTextNode[] =>
      Array.from({ length: count(4) }, () =>
        random() < 0.2 ? hardBreak : text(pick(words), ...pick(marks)),
      );
    const block = (depth: number): RichTextNode => {
      const kind = depth > 2 ? 0 : count(5);
      if (kind === 1) {
        return {
          content: Array.from({ length: 1 + count(3) }, () => block(depth + 1)),
          type: "blockquote",
        };
      }
      if (kind === 2) {
        return {
          content: Array.from({ length: 1 + count(3) }, () =>
            listItem(
              paragraph(...inline()),
              ...Array.from({ length: count(2) }, () => block(depth + 1)),
            ),
          ),
          type: pick(["bulletList", "orderedList"]),
        };
      }
      if (kind === 3) {
        return random() < 0.8
          ? { content: [text(pick(["\n x ", " y\n", "z"]))], type: "codeBlock" }
          : { type: "codeBlock" };
      }
      return paragraph(...inline());
    };

    for (let iteration = 0; iteration < 500; iteration += 1) {
      const document = doc(
        ...Array.from({ length: 1 + count(5) }, () => block(0)),
      );
      expect(() => editorSchema.nodeFromJSON(document).check()).not.toThrow();
      const value = editorValue(document);
      const trimmed = trimEntryNote(value.text, value);

      expect(trimmed.body).toBe(value.text.trim());
      expect(trimEntryNote(trimmed.body, trimmed.bodyRich)).toEqual(trimmed);
      if (!trimmed.body) {
        expect(trimmed.bodyRich).toBeNull();
        continue;
      }
      expect(isEntryRichText(trimmed.bodyRich, trimmed.body)).toBe(true);
      expectEditorDocument(trimmed.bodyRich);
      if (value.text === trimmed.body) {
        expect(trimmed.bodyRich!.document).toEqual(document);
      }
    }
  });
});
