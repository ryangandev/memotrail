import type { RichTextNode } from "@/lib/data/rich-text";
import { markdownToBlocks } from "./convert-markdown";
import { newContext } from "./convert-html";

export type ConvertedNote = {
  title: string | null;
  /** Where the title came from. A title taken from the file name alone is not content. */
  titleSource: "frontmatter" | "heading" | "fallback" | null;
  blocks: RichTextNode[];
  images: { src: string; alt: string }[];
  skipped: Map<string, number>;
  tags: string[];
};

const leadingHeading = /^\s*#[ \t]+(.+?)[ \t]*#*[ \t]*(?:\r?\n|$)/;

/**
 * One Markdown note as a title and blocks. The title is the frontmatter title, else a first
 * line heading (which then is not repeated in the body), else the fallback, usually the file
 * name.
 */
export function convertMarkdownNote(
  markdown: string,
  titleFallback: string | null,
  options: { collectHashtags: boolean; frontmatterTitle?: string | null },
): ConvertedNote {
  let body = markdown;
  let title = options.frontmatterTitle?.trim() || null;
  let titleSource: ConvertedNote["titleSource"] = title ? "frontmatter" : null;
  if (!title) {
    const heading = leadingHeading.exec(body);
    if (heading) {
      title = heading[1].trim();
      body = body.slice(heading[0].length);
      titleSource = "heading";
    }
  }
  if (!title) {
    title = titleFallback?.trim() || null;
    titleSource = title ? "fallback" : null;
  }
  const ctx = newContext(options.collectHashtags);
  const blocks = markdownToBlocks(body, ctx);
  return {
    blocks,
    images: ctx.images,
    skipped: ctx.skipped,
    tags: ctx.tags,
    title,
    titleSource,
  };
}
