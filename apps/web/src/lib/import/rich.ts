import {
  createEntryRichText,
  plainTextDocument,
  plainTextFromDocument,
  trimEntryNote,
  type EntryRichText,
  type RichTextDocument,
  type RichTextMark,
  type RichTextNode,
} from "@/lib/data/rich-text";
import { importLimits } from "./limits";

/**
 * Building the rich text an imported Entry can hold. Entries support paragraphs, quotes,
 * bullet and numbered lists, code blocks, line breaks, and bold, italic, underline,
 * strikethrough, code, and link marks, and nothing else. Converters build only these nodes,
 * so an import can never inject markup the editor does not know.
 */

const allowedLinkProtocols = new Set(["http:", "https:", "mailto:"]);

/** A link the Entry may keep, or null so the link is dropped and its text stays. */
export function safeHref(href: string | undefined | null): string | null {
  if (!href) return null;
  const trimmed = href.trim();
  if (trimmed.length === 0 || trimmed.length > 2048) return null;
  try {
    const url = new URL(trimmed);
    return allowedLinkProtocols.has(url.protocol) ? url.toString() : null;
  } catch {
    return null;
  }
}

export const bold: RichTextMark = { type: "bold" };
export const italic: RichTextMark = { type: "italic" };
export const underline: RichTextMark = { type: "underline" };
export const strike: RichTextMark = { type: "strike" };
export const codeMark: RichTextMark = { type: "code" };
export function linkMark(href: string): RichTextMark {
  return { attrs: { href }, type: "link" };
}

export function textNodes(
  text: string,
  marks: RichTextMark[] = [],
): RichTextNode[] {
  const nodes: RichTextNode[] = [];
  text
    .replace(/\r\n?/g, "\n")
    .split("\n")
    .forEach((line, index) => {
      if (index > 0) nodes.push({ type: "hardBreak" });
      if (line.length > 0)
        nodes.push({
          ...(marks.length > 0
            ? { marks: marks.map((mark) => ({ ...mark })) }
            : {}),
          text: line,
          type: "text",
        });
    });
  return nodes;
}

export function withMark(
  nodes: RichTextNode[],
  mark: RichTextMark,
): RichTextNode[] {
  return nodes.map((node) =>
    node.type === "text"
      ? { ...node, marks: [...(node.marks ?? []), mark] }
      : node,
  );
}

const markKey = (marks: RichTextMark[] | undefined) =>
  JSON.stringify(marks ?? []);

/** Joins neighboring text with the same marks and drops empty text. */
export function mergeInline(nodes: RichTextNode[]): RichTextNode[] {
  const merged: RichTextNode[] = [];
  for (const node of nodes) {
    if (node.type === "text") {
      if (!node.text) continue;
      const last = merged.at(-1);
      if (
        last?.type === "text" &&
        markKey(last.marks) === markKey(node.marks)
      ) {
        last.text = (last.text ?? "") + node.text;
        continue;
      }
      merged.push({ ...node });
    } else if (node.type === "hardBreak") {
      merged.push({ type: "hardBreak" });
    }
  }
  return merged;
}

export function paragraph(inline: RichTextNode[]): RichTextNode {
  const content = mergeInline(inline);
  return content.length > 0
    ? { content, type: "paragraph" }
    : { type: "paragraph" };
}

export function isBlankBlock(node: RichTextNode) {
  return plainTextFromDocument(docOf([node])).trim() === "";
}

export function docOf(blocks: RichTextNode[]): RichTextDocument {
  return {
    content: blocks.length > 0 ? blocks : [{ type: "paragraph" }],
    type: "doc",
  };
}

export function bulletList(items: RichTextNode[][]): RichTextNode {
  return {
    content: items.map((blocks) => listItem(blocks)),
    type: "bulletList",
  };
}

export function orderedList(items: RichTextNode[][], start = 1): RichTextNode {
  return {
    ...(start !== 1 ? { attrs: { start } } : {}),
    content: items.map((blocks) => listItem(blocks)),
    type: "orderedList",
  };
}

/** A list item always starts with a paragraph. */
export function listItem(blocks: RichTextNode[]): RichTextNode {
  const content = blocks.length > 0 ? blocks : [{ type: "paragraph" }];
  return {
    content:
      content[0].type === "paragraph"
        ? content
        : [{ type: "paragraph" }, ...content],
    type: "listItem",
  };
}

export function blockquote(blocks: RichTextNode[]): RichTextNode {
  return {
    content: blocks.length > 0 ? blocks : [{ type: "paragraph" }],
    type: "blockquote",
  };
}

export function codeBlock(
  text: string,
  language?: string | null,
): RichTextNode {
  const attrs =
    language && /^[A-Za-z0-9_+#.-]{1,40}$/.test(language)
      ? { attrs: { language } }
      : {};
  const clean = text.replace(/\r\n?/g, "\n").replace(/\n$/, "");
  return {
    ...attrs,
    ...(clean ? { content: [{ text: clean, type: "text" }] } : {}),
    type: "codeBlock",
  };
}

/** Plain paragraphs for text, one per line. */
export function paragraphsFromText(text: string): RichTextNode[] {
  return plainTextDocument(text).content;
}

function countNodes(node: RichTextNode): number {
  return (
    1 + (node.content ?? []).reduce((sum, child) => sum + countNodes(child), 0)
  );
}

function measure(block: RichTextNode) {
  return {
    bytes: JSON.stringify(block).length,
    chars: plainTextFromDocument(docOf([block])).length,
    nodes: countNodes(block),
  };
}

/** Cuts text into pieces that fit a part, at a line, space, or (last) a hard limit. */
function chunkText(text: string): string[] {
  const chunks: string[] = [];
  for (let line of text.split("\n")) {
    while (line.length > importLimits.partChars) {
      let cut = line.lastIndexOf(" ", importLimits.partChars);
      if (cut < importLimits.partChars / 2) cut = importLimits.partChars;
      chunks.push(line.slice(0, cut));
      line = line.slice(cut).trimStart();
    }
    chunks.push(line);
  }
  return chunks;
}

export type BodyPart = {
  /** The plain body, always equal to the rich text's text. */
  body: string;
  richText: EntryRichText | null;
  document: RichTextDocument;
};

/**
 * Turns blocks into the bodies of one or more Entries. A body is cut into parts when it
 * would pass the Entry limits, at block boundaries first and inside a block only when one
 * block alone is too long. Every part is checked with the editor's own validator and falls
 * back to plain text when formatting cannot be kept.
 */
export function bodyParts(blocks: RichTextNode[]): BodyPart[] {
  const fitted: RichTextNode[] = [];
  for (const block of blocks) {
    const size = measure(block);
    if (
      size.chars > importLimits.partChars ||
      size.nodes > importLimits.partNodes ||
      size.bytes > importLimits.partBytes
    ) {
      const text = plainTextFromDocument(docOf([block]));
      for (const chunk of chunkText(text))
        fitted.push(...paragraphsFromText(chunk));
    } else fitted.push(block);
  }

  const groups: RichTextNode[][] = [];
  let current: RichTextNode[] = [];
  let chars = 0;
  let nodes = 0;
  let bytes = 0;
  for (const block of fitted) {
    const size = measure(block);
    if (
      current.length > 0 &&
      (chars + size.chars + 1 > importLimits.partChars ||
        nodes + size.nodes > importLimits.partNodes ||
        bytes + size.bytes > importLimits.partBytes)
    ) {
      groups.push(current);
      current = [];
      chars = 0;
      nodes = 0;
      bytes = 0;
    }
    current.push(block);
    chars += size.chars + 1;
    nodes += size.nodes;
    bytes += size.bytes;
  }
  if (current.length > 0) groups.push(current);
  if (groups.length === 0) groups.push([]);

  return groups.map((group) => {
    const document = docOf(group);
    const rich = createEntryRichText(document);
    const text = rich?.text ?? plainTextFromDocument(document);
    const trimmed = trimEntryNote(text, rich);
    if (trimmed.bodyRich || trimmed.body === "") {
      return {
        body: trimmed.body,
        document: trimmed.bodyRich?.document ?? docOf([]),
        richText: trimmed.bodyRich,
      };
    }
    // Formatting the editor cannot hold: keep the words.
    const plain = plainTextDocument(trimmed.body);
    const plainRich = createEntryRichText(plain);
    return { body: trimmed.body, document: plain, richText: plainRich };
  });
}

export function plainTextOf(document: RichTextDocument) {
  return plainTextFromDocument(document);
}
