import {
  createEntryRichText,
  type EntryRichText,
  type RichTextDocument,
  type RichTextNode,
} from "@/lib/data/rich-text";

// Local sample content for the gallery. The iOS gallery draws the same samples in
// GallerySamples, so both galleries review the same records.

/** The sample coast landscape, drawn inline so specimens need no network image. */
export const loadedImage =
  "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='640' height='360' viewBox='0 0 640 360'%3E%3Crect width='640' height='360' fill='%23DDE8E1'/%3E%3Cpath d='M0 285 190 115l112 95 90-72 248 147v75H0Z' fill='%2382AD98'/%3E%3Ccircle cx='492' cy='92' r='38' fill='%23A76346'/%3E%3C/svg%3E";

/** The landscape turned upright, so cover and contain crop it differently in a wide frame. */
export const tallImage =
  "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='360' height='640' viewBox='0 0 360 640'%3E%3Crect width='360' height='640' fill='%23DDE8E1'/%3E%3Cpath d='M0 506 107 204l63 169 51-128 139 261v134H0Z' fill='%2382AD98'/%3E%3Ccircle cx='277' cy='164' r='38' fill='%23A76346'/%3E%3C/svg%3E";

/** Three saved photos on an Entry, for the photo viewer. */
export const samplePhotos = [
  "kitchen-window.jpg",
  "maple-in-october.jpg",
  "front-steps.jpg",
].map((name) => ({ id: name, name, src: loadedImage }));

const text = (value: string, marks?: string[]): RichTextNode => ({
  ...(marks ? { marks: marks.map((type) => ({ type })) } : {}),
  text: value,
  type: "text",
});
const paragraph = (...content: RichTextNode[]): RichTextNode => ({
  content,
  type: "paragraph",
});
const item = (...content: RichTextNode[]): RichTextNode => ({
  content: [paragraph(...content)],
  type: "listItem",
});

const richTextDocument: RichTextDocument = {
  content: [
    paragraph(
      text("Formatted memory", ["bold"]),
      text(" with durable, validated structure."),
    ),
    paragraph(
      text("We walked to the "),
      text("old lighthouse", ["italic"]),
      text(", checked the "),
      text("tide table", ["code"]),
      text(", and "),
      {
        marks: [
          { attrs: { href: "https://example.com/lighthouse" }, type: "link" },
        ],
        text: "saved the map",
        type: "text",
      },
      text("."),
    ),
    {
      content: [paragraph(text("The wind was louder than the waves."))],
      type: "blockquote",
    },
    {
      content: [
        item(text("One remembered detail")),
        item(text("Another", ["underline"]), text(" worth keeping")),
      ],
      type: "bulletList",
    },
    {
      attrs: { start: 3 },
      content: [
        item(text("Pack the thermos")),
        item(text("Leave early", ["strike"]), text(" Leave when ready")),
      ],
      type: "orderedList",
    },
    {
      content: [text("sunrise 06:42\nsunset  19:08")],
      type: "codeBlock",
    },
    paragraph(text("第一次沿着海岸慢慢走。")),
  ],
  type: "doc",
};

/** A saved note with every block and mark iOS reads, matching GallerySamples.richText. */
export const sampleRichText = createEntryRichText(
  richTextDocument,
) as EntryRichText;
