import { describe, expect, it } from "vitest";
import { createEntryRichText, plainTextFromDocument } from "@/lib/data/rich-text";
import { htmlToBlocks, newContext } from "./convert-html";
import { markdownToBlocks } from "./convert-markdown";
import { bodyParts, docOf, paragraph, safeHref, textNodes } from "./rich";

describe("rich text for imports", () => {
  it("keeps only safe link schemes", () => {
    expect(safeHref("https://example.com/a")).toBe("https://example.com/a");
    expect(safeHref("mailto:a@example.com")).toBe("mailto:a@example.com");
    expect(safeHref("javascript:alert(1)")).toBeNull();
    expect(safeHref("data:text/html,x")).toBeNull();
    expect(safeHref("notes/other.md")).toBeNull();
  });

  it("builds a body whose text always matches its rich text and passes the editor's validator", () => {
    const blocks = markdownToBlocks(
      [
        "# Heading",
        "",
        "Some **bold**, *italic*, ~~gone~~ and `code`.",
        "",
        "> A quote",
        "",
        "1. one",
        "2. two",
        "",
        "- [ ] todo",
        "- [x] done",
        "",
        "```js",
        "const a = 1;",
        "```",
      ].join("\n"),
      newContext(),
    );
    const [part] = bodyParts(blocks);
    expect(part.richText).not.toBeNull();
    expect(createEntryRichText(part.richText!.document)).not.toBeNull();
    expect(part.richText!.text).toBe(part.body);
    expect(plainTextFromDocument(part.document)).toBe(part.body);
    expect(part.body).toContain("Heading");
    expect(part.body).toContain("[x] done");
  });

  it("degrades callouts, tables, scripts, and unknown tags from HTML", () => {
    const ctx = newContext();
    const blocks = htmlToBlocks(
      `<aside>Note this</aside><table><tr><td>a</td><td>b</td></tr></table><script>boom()</script><custom-tag>kept text</custom-tag><img src="pic.png" alt="a" /><video src="v.mov"></video>`,
      ctx,
    );
    const text = plainTextFromDocument(docOf(blocks));
    expect(blocks[0].type).toBe("blockquote");
    expect(text).toContain("Note this");
    expect(text).toContain("a\tb");
    expect(text).toContain("kept text");
    expect(text).not.toContain("boom");
    expect(ctx.images).toEqual([{ alt: "a", src: "pic.png" }]);
    expect(ctx.skipped.get("video")).toBe(1);
  });

  it("splits what is too long, at block boundaries, within the Entry limits", () => {
    const blocks = Array.from({ length: 80 }, (_, i) =>
      paragraph(textNodes(`Block ${i} ${"lorem ".repeat(150)}`)),
    );
    const parts = bodyParts(blocks);
    expect(parts.length).toBeGreaterThan(1);
    for (const part of parts) {
      expect(part.body.length).toBeLessThanOrEqual(50_000);
      expect(part.richText?.text).toBe(part.body);
    }
    expect(parts.map((part) => part.body).join("\n")).toContain("Block 79");
  });

  it("cuts a single enormous paragraph into pieces", () => {
    const parts = bodyParts([paragraph(textNodes("word ".repeat(30_000)))]);
    expect(parts.length).toBeGreaterThan(1);
    for (const part of parts) expect(part.body.length).toBeLessThanOrEqual(50_000);
  });

  it("falls back to plain text when there are too many formatted runs", () => {
    const runs = Array.from({ length: 5_000 }, (_, i) =>
      textNodes(`w${i}`, i % 2 ? [{ type: "bold" }] : [{ type: "italic" }])[0],
    );
    const parts = bodyParts([paragraph(runs)]);
    for (const part of parts) expect(part.richText).not.toBeNull();
  });

  it("reports an empty body", () => {
    expect(bodyParts([])[0].body).toBe("");
  });
});
