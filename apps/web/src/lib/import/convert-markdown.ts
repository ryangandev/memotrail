import remarkGfm from "remark-gfm";
import remarkParse from "remark-parse";
import { unified } from "unified";
import type {
  Blockquote,
  Code,
  List,
  ListItem,
  Nodes,
  PhrasingContent,
  Root,
  RootContent,
  Table,
} from "mdast";
import type { RichTextMark, RichTextNode } from "@/lib/data/rich-text";
import {
  cleanBlocks,
  htmlToBlocks,
  trimInline,
  type ConvertContext,
} from "./convert-html";
import {
  blockquote,
  bold,
  bulletList,
  codeBlock,
  codeMark,
  italic,
  linkMark,
  mergeInline,
  orderedList,
  paragraph,
  safeHref,
  strike,
  textNodes,
} from "./rich";

const parser = unified().use(remarkParse).use(remarkGfm);

/**
 * Turns Markdown into the blocks an Entry can hold. Headings become bold paragraphs, tables
 * become tab separated lines, HTML blocks go through the HTML converter, wikilinks keep their
 * label, and pictures are collected into the context instead of the text.
 */
export function markdownToBlocks(
  markdown: string,
  ctx: ConvertContext,
): RichTextNode[] {
  const tree = parser.parse(markdown) as Root;
  return cleanBlocks(blocksOf(tree.children, ctx));
}

function blocksOf(nodes: RootContent[], ctx: ConvertContext): RichTextNode[] {
  return nodes.flatMap((node) => blockOf(node, ctx));
}

function blockOf(node: RootContent, ctx: ConvertContext): RichTextNode[] {
  switch (node.type) {
    case "paragraph":
      return [
        paragraph(
          trimInline(mergeInline(inlineList(node.children, ctx, [], true))),
        ),
      ];
    case "heading":
      return [
        paragraph(
          trimInline(
            mergeInline(inlineList(node.children, ctx, [bold], false)),
          ),
        ),
      ];
    case "blockquote":
      return [
        blockquote(cleanBlocks(blocksOf((node as Blockquote).children, ctx))),
      ];
    case "list":
      return [listOf(node as List, ctx)];
    case "code":
      return [codeBlock((node as Code).value, (node as Code).lang)];
    case "html":
      return htmlToBlocks(node.value, ctx);
    case "table":
      return tableOf(node as Table, ctx);
    case "footnoteDefinition":
      return cleanBlocks(blocksOf(node.children, ctx));
    case "thematicBreak":
    case "definition":
    case "yaml":
      return [];
    default:
      return [];
  }
}

function listOf(list: List, ctx: ConvertContext): RichTextNode {
  const items = list.children.map((item) => itemBlocks(item, ctx));
  return list.ordered ? orderedList(items, list.start ?? 1) : bulletList(items);
}

function itemBlocks(item: ListItem, ctx: ConvertContext): RichTextNode[] {
  const blocks = cleanBlocks(blocksOf(item.children, ctx));
  if (typeof item.checked === "boolean") {
    const box = item.checked ? "[x] " : "[ ] ";
    const first = blocks[0];
    if (first?.type === "paragraph")
      first.content = [...textNodes(box), ...(first.content ?? [])];
    else blocks.unshift(paragraph(textNodes(box.trim())));
  }
  return blocks;
}

function tableOf(table: Table, ctx: ConvertContext): RichTextNode[] {
  return table.children.map((row) => {
    const line: RichTextNode[] = [];
    row.children.forEach((cell, index) => {
      if (index > 0) line.push(...textNodes("\t"));
      line.push(
        ...trimInline(mergeInline(inlineList(cell.children, ctx, [], false))),
      );
    });
    return paragraph(line);
  });
}

const wikiEmbed = /!\[\[([^\]\n]+)\]\]/g;
const wikiLink = /\[\[([^\]\n]+)\]\]/g;
const hashtag = /(^|[\s(])#([\p{L}\p{N}_/-]*[\p{L}_/-][\p{L}\p{N}_/-]*)/gu;

/** Text with Obsidian wikilinks flattened and embedded pictures collected. */
function textWithWikilinks(
  value: string,
  ctx: ConvertContext,
  marks: RichTextMark[],
  tags: boolean,
): RichTextNode[] {
  let text = value.replace(wikiEmbed, (_match, inner: string) => {
    const target = inner.split("|")[0].trim();
    if (target) ctx.images.push({ alt: "", src: target });
    return "";
  });
  text = text.replace(wikiLink, (_match, inner: string) => {
    const [target, alias] = inner.split("|");
    return (alias ?? target.split("#")[0] ?? target).trim();
  });
  if (tags && ctx.collectHashtags) {
    for (const match of text.matchAll(hashtag)) ctx.tags.push(match[2]);
  }
  return textNodes(text, marks);
}

function inlineList(
  nodes: PhrasingContent[],
  ctx: ConvertContext,
  marks: RichTextMark[],
  tags: boolean,
): RichTextNode[] {
  return nodes.flatMap((node) => inlineOf(node, ctx, marks, tags));
}

function inlineOf(
  node: PhrasingContent | Nodes,
  ctx: ConvertContext,
  marks: RichTextMark[],
  tags: boolean,
): RichTextNode[] {
  switch (node.type) {
    case "text":
      return textWithWikilinks(node.value, ctx, marks, tags);
    case "strong":
      return inlineList(node.children, ctx, [...marks, bold], tags);
    case "emphasis":
      return inlineList(node.children, ctx, [...marks, italic], tags);
    case "delete":
      return inlineList(node.children, ctx, [...marks, strike], tags);
    case "inlineCode":
      return textNodes(node.value, [...marks, codeMark]);
    case "break":
      return [{ type: "hardBreak" }];
    case "link": {
      const href = safeHref(node.url);
      return inlineList(
        node.children,
        ctx,
        href ? [...marks, linkMark(href)] : marks,
        false,
      );
    }
    case "linkReference":
      return inlineList(node.children, ctx, marks, false);
    case "image":
    case "imageReference": {
      const alt = (node.alt ?? "").trim();
      const src = node.type === "image" ? node.url : "";
      if (node.type === "image") {
        if (/^https?:\/\//i.test(src)) {
          // A picture hosted elsewhere is not copied. Its address stays as a link.
          const href = safeHref(src);
          return textNodes(
            alt || src,
            href ? [...marks, linkMark(href)] : marks,
          );
        }
        ctx.images.push({ alt, src });
      }
      return alt.split(/\s+/).length > 3 ? textNodes(alt, marks) : [];
    }
    case "html": {
      const tag = /^<\s*br\s*\/?>$/i.test(node.value.trim());
      return tag ? [{ type: "hardBreak" }] : [];
    }
    case "footnoteReference":
      return textNodes(`[${node.label ?? node.identifier}]`, marks);
    default:
      return [];
  }
}
