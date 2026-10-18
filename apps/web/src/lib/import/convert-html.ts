import { parseFragment } from "parse5";
import type { DefaultTreeAdapterMap } from "parse5";
import type { RichTextMark, RichTextNode } from "@/lib/data/rich-text";
import {
  blockquote,
  bold,
  bulletList,
  codeBlock,
  codeMark,
  isBlankBlock,
  italic,
  linkMark,
  mergeInline,
  orderedList,
  paragraph,
  safeHref,
  strike,
  textNodes,
  underline,
} from "./rich";

type Node = DefaultTreeAdapterMap["node"];
type Element = DefaultTreeAdapterMap["element"];
type TextNode = DefaultTreeAdapterMap["textNode"];

/** What conversion found besides text: pictures and other files the Entry may use. */
export type ConvertContext = {
  /** Image references in the order the body used them. */
  images: { src: string; alt: string }[];
  /** Files that are not photos, counted by kind, for the "not imported" summary. */
  skipped: Map<string, number>;
  /** Hashtags found in the text, when the source uses them as tags. */
  tags: string[];
  collectHashtags: boolean;
};

export function newContext(collectHashtags = false): ConvertContext {
  return { collectHashtags, images: [], skipped: new Map(), tags: [] };
}

export function noteSkipped(ctx: ConvertContext, kind: string, count = 1) {
  ctx.skipped.set(kind, (ctx.skipped.get(kind) ?? 0) + count);
}

const dropped = new Set([
  "script",
  "style",
  "head",
  "svg",
  "canvas",
  "template",
  "noscript",
  "iframe",
  "object",
  "embed",
  "link",
  "meta",
  "title",
]);
const blockTags = new Set([
  "address",
  "article",
  "aside",
  "blockquote",
  "details",
  "div",
  "dl",
  "dd",
  "dt",
  "fieldset",
  "figcaption",
  "figure",
  "footer",
  "form",
  "h1",
  "h2",
  "h3",
  "h4",
  "h5",
  "h6",
  "header",
  "hr",
  "li",
  "main",
  "nav",
  "ol",
  "p",
  "pre",
  "section",
  "summary",
  "table",
  "tbody",
  "td",
  "tfoot",
  "th",
  "thead",
  "tr",
  "ul",
]);
const headingTags = new Set(["h1", "h2", "h3", "h4", "h5", "h6"]);

const isElement = (node: Node): node is Element => "tagName" in node;
const isText = (node: Node): node is TextNode => node.nodeName === "#text";

function attribute(element: Element, name: string) {
  return element.attrs.find((attr) => attr.name === name)?.value;
}

function elementChildren(node: Node): Node[] {
  if (isElement(node) && node.tagName === "template") return [];
  return "childNodes" in node ? node.childNodes : [];
}

/**
 * Turns an HTML fragment into the blocks an Entry can hold. Unknown markup keeps its text,
 * scripts and styles are dropped, and nothing in the HTML survives as markup: only the node
 * kinds the Entry supports are produced.
 */
export function htmlToBlocks(html: string, ctx: ConvertContext): RichTextNode[] {
  const fragment = parseFragment(html);
  return cleanBlocks(containerBlocks(fragment.childNodes, ctx, []));
}

/** Plain text of some HTML, for short values such as a title. */
export function htmlText(html: string): string {
  const out: string[] = [];
  const walk = (nodes: Node[]) => {
    for (const node of nodes) {
      if (isText(node)) out.push(node.value);
      else if (isElement(node)) {
        if (dropped.has(node.tagName)) continue;
        if (node.tagName === "br") out.push("\n");
        walk(elementChildren(node));
        if (blockTags.has(node.tagName)) out.push("\n");
      }
    }
  };
  walk(parseFragment(html).childNodes);
  return out.join("").replace(/[ \t]+/g, " ").replace(/\n\s*\n+/g, "\n").trim();
}

/** Removes blocks with no words. Code blocks keep their blank lines. */
export function cleanBlocks(blocks: RichTextNode[]): RichTextNode[] {
  return blocks.filter((block) => block.type === "codeBlock" || !isBlankBlock(block));
}

/** Children of a container: runs of inline content become paragraphs, blocks stay blocks. */
function containerBlocks(
  nodes: Node[],
  ctx: ConvertContext,
  marks: RichTextMark[],
): RichTextNode[] {
  const blocks: RichTextNode[] = [];
  let run: RichTextNode[] = [];
  const flush = () => {
    const inline = trimInline(mergeInline(run));
    if (inline.length > 0) blocks.push(paragraph(inline));
    run = [];
  };
  for (const node of nodes) {
    if (isElement(node) && blockTags.has(node.tagName)) {
      flush();
      blocks.push(...blockElement(node, ctx, marks));
    } else {
      run.push(...inlineNode(node, ctx, marks));
    }
  }
  flush();
  return blocks;
}

function blockElement(
  element: Element,
  ctx: ConvertContext,
  marks: RichTextMark[],
): RichTextNode[] {
  const tag = element.tagName;
  const children = elementChildren(element);
  if (headingTags.has(tag)) {
    return [
      paragraph(
        trimInline(mergeInline(inlineList(children, ctx, [...marks, bold]))),
      ),
    ];
  }
  switch (tag) {
    case "hr":
      return [];
    case "p":
      return [paragraph(trimInline(mergeInline(inlineList(children, ctx, marks))))];
    case "blockquote":
    case "aside":
    case "details":
      return [blockquote(cleanBlocks(containerBlocks(children, ctx, marks)))];
    case "pre": {
      const text = textOf(children);
      return [codeBlock(text)];
    }
    case "ul":
    case "ol": {
      const items = children
        .filter((child) => isElement(child) && child.tagName === "li")
        .map((child) => cleanBlocks(containerBlocks(elementChildren(child), ctx, marks)));
      if (items.length === 0) return [];
      const start = Number(attribute(element, "start"));
      return [
        tag === "ul"
          ? bulletList(items)
          : orderedList(items, Number.isInteger(start) && start > 0 ? start : 1),
      ];
    }
    case "li":
      return cleanBlocks(containerBlocks(children, ctx, marks));
    case "table":
      return tableBlocks(element, ctx, marks);
    default:
      return containerBlocks(children, ctx, marks);
  }
}

/** A table has no node in the Entry, so each row becomes a line of tab separated cells. */
function tableBlocks(
  table: Element,
  ctx: ConvertContext,
  marks: RichTextMark[],
): RichTextNode[] {
  const rows: Element[] = [];
  const find = (nodes: Node[]) => {
    for (const node of nodes) {
      if (!isElement(node)) continue;
      if (node.tagName === "tr") rows.push(node);
      else if (node.tagName !== "table") find(elementChildren(node));
    }
  };
  find(elementChildren(table));
  return rows.map((row) => {
    const cells = elementChildren(row)
      .filter((cell) => isElement(cell) && (cell.tagName === "td" || cell.tagName === "th"))
      .map((cell) => trimInline(mergeInline(inlineList(elementChildren(cell), ctx, marks))));
    const line: RichTextNode[] = [];
    cells.forEach((cell, index) => {
      if (index > 0) line.push(...textNodes("\t"));
      line.push(...cell);
    });
    return paragraph(line);
  });
}

function textOf(nodes: Node[]): string {
  return nodes
    .map((node) =>
      isText(node)
        ? node.value
        : isElement(node)
          ? node.tagName === "br"
            ? "\n"
            : textOf(elementChildren(node))
          : "",
    )
    .join("");
}

function inlineList(
  nodes: Node[],
  ctx: ConvertContext,
  marks: RichTextMark[],
): RichTextNode[] {
  return nodes.flatMap((node) => inlineNode(node, ctx, marks));
}

function inlineNode(
  node: Node,
  ctx: ConvertContext,
  marks: RichTextMark[],
): RichTextNode[] {
  if (isText(node)) {
    // HTML collapses whitespace, including line breaks, to single spaces.
    const text = node.value.replace(/\s+/g, " ");
    return text ? textNodes(text, marks) : [];
  }
  if (!isElement(node)) return [];
  const tag = node.tagName;
  if (dropped.has(tag)) return [];
  const children = elementChildren(node);
  switch (tag) {
    case "br":
      return [{ type: "hardBreak" }];
    case "b":
    case "strong":
      return inlineList(children, ctx, [...marks, bold]);
    case "i":
    case "em":
    case "cite":
      return inlineList(children, ctx, [...marks, italic]);
    case "u":
    case "ins":
      return inlineList(children, ctx, [...marks, underline]);
    case "s":
    case "strike":
    case "del":
      return inlineList(children, ctx, [...marks, strike]);
    case "code":
    case "kbd":
    case "samp":
    case "tt":
      return inlineList(children, ctx, [...marks, codeMark]);
    case "a": {
      const href = safeHref(attribute(node, "href"));
      const inner = inlineList(children, ctx, href ? [...marks, linkMark(href)] : marks);
      return inner;
    }
    case "img": {
      const src = attribute(node, "src") ?? "";
      const alt = (attribute(node, "alt") ?? "").trim();
      if (src) ctx.images.push({ alt, src });
      return alt.split(/\s+/).length > 3 ? textNodes(alt, marks) : [];
    }
    case "video":
      noteSkipped(ctx, "video");
      return [];
    case "audio":
      noteSkipped(ctx, "audio");
      return [];
    default:
      return inlineList(children, ctx, marks);
  }
}

/** Strips spaces from the start and end of a line of inline nodes. */
export function trimInline(nodes: RichTextNode[]): RichTextNode[] {
  const result = nodes.map((node) => ({ ...node }));
  while (result.length > 0) {
    const first = result[0];
    if (first.type === "hardBreak") {
      result.shift();
      continue;
    }
    first.text = (first.text ?? "").trimStart();
    if (first.text === "") result.shift();
    else break;
  }
  while (result.length > 0) {
    const last = result[result.length - 1];
    if (last.type === "hardBreak") {
      result.pop();
      continue;
    }
    last.text = (last.text ?? "").trimEnd();
    if (last.text === "") result.pop();
    else break;
  }
  return result;
}
