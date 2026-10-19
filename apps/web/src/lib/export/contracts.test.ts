import { describe, expect, it } from "vitest";
import {
  EXPORT_COMPLETE,
  EXPORT_TAIL_BYTES,
  appendExportTail,
  csvCell,
  entryMarkdown,
  entryTableHeader,
  entryTableLine,
  hasCompleteExport,
  mediaArchivePath,
  parseExportAction,
  reviewMarkdown,
} from "./contracts";
const id = "00000000-0000-0000-0000-000000000001";
describe("portable export contracts", () => {
  it("allows only exact owner-scoped actions and UUIDs", () => {
    expect(parseExportAction({ action: "list" })).toEqual({ action: "list" });
    for (const action of ["create", "discard", "download"])
      expect(parseExportAction({ action, id })).toEqual({ action, id });
    for (const bad of [
      null,
      [],
      { action: "list", id },
      { action: "download", id: "../private" },
      { action: "create", id, ownerID: id },
      { action: "drop", id },
    ])
      expect(parseExportAction(bad)).toBeNull();
  });
  it("canonicalizes a native client's uppercase UUID", () => {
    expect(
      parseExportAction({
        action: "download",
        id: "4F8D0FE6-61D0-418A-8713-CF071AEEA450",
      }),
    ).toEqual({
      action: "download",
      id: "4f8d0fe6-61d0-418a-8713-cf071aeea450",
    });
  });
  it("preserves Unicode, precision and original writing in Markdown without title path injection", () => {
    const body = "我的记录\n\n# untouched\n[link](https://example.test)";
    const result = entryMarkdown({
      id,
      title: '"\n---\n../title',
      body,
      occurred_start: null,
      occurred_end: null,
      date_precision: "age",
      occurred_label: "17岁",
      occurred_timezone: "Asia/Shanghai",
    });
    expect(result).toContain('date_precision: "age"');
    expect(result).toContain('occurred_label: "17岁"');
    expect(result).toContain("occurred_start: null");
    expect(result).toContain('title: "\\"\\n---\\n../title"');
    expect(result.endsWith(body + "\n")).toBe(true);
  });
  it("records the Chapter and First Time marks in the Markdown frontmatter", () => {
    const result = entryMarkdown({
      id,
      title: "Living in Portland",
      body: "Moved in March.",
      item_kind: "entry",
      item_subtype: "chapter",
      is_first_time: true,
      date_precision: "month",
    });
    const lines = result.split("\n");
    expect(lines).toContain('item_subtype: "chapter"');
    expect(lines).toContain("is_first_time: true");
    expect(lines.indexOf("is_first_time: true")).toBe(
      lines.indexOf('item_subtype: "chapter"') + 1,
    );
  });
  it("writes a readable Entries table with the marks and no writing", () => {
    expect(entryTableHeader()).toBe(
      '"id","title","item_subtype","is_first_time","date_precision","occurred_start","occurred_end","occurred_label","occurred_timezone","created_at","updated_at","deleted_at"\r\n',
    );
    const line = entryTableLine({
      id,
      title: "=HYPERLINK(1)",
      body: "Private writing stays in entries/*.md",
      item_subtype: "chapter",
      is_first_time: false,
      date_precision: "month",
      occurred_start: "2019-03-01T12:00:00Z",
      occurred_end: null,
      occurred_label: null,
      occurred_timezone: "UTC",
      created_at: "2026-09-12T00:00:00Z",
      updated_at: "2026-09-12T00:00:00Z",
      deleted_at: null,
    });
    expect(line).toContain(`"'=HYPERLINK(1)","chapter","false","month"`);
    expect(line).not.toContain("Private writing");
    expect(line.endsWith('"\r\n')).toBe(true);
    expect(line.split(",")).toHaveLength(12);
  });
  it("quotes CSV safely without changing canonical values", () => {
    expect(csvCell('中文,"hello"\nnext')).toBe('"中文,""hello""\nnext"');
    for (const text of ["=1+1", "+cmd", "-1", "@SUM(A1)", "\t =1", "\r\n-2"])
      expect(csvCell(text)).toBe(`"'${text}"`);
    expect(csvCell(-2)).toBe('"-2"');
    expect(csvCell(null)).toBe('""');
    expect(csvCell({ id })).toContain(id);
  });
  it("uses only attachment identity and a safe known variant in ZIP paths", () => {
    expect(
      mediaArchivePath({
        attachment_id: id,
        variant: "display",
        object_path: "owner/../../photo.PNG",
      }),
    ).toBe(`media/${id}-display.png`);
    expect(
      mediaArchivePath({
        attachment_id: id,
        variant: "original",
        object_path: "photo.weird/path",
      }),
    ).toBe(`media/${id}-original.bin`);
    expect(() =>
      mediaArchivePath({ attachment_id: "../secret", variant: "original" }),
    ).toThrow();
    expect(() =>
      mediaArchivePath({ attachment_id: id, variant: "../../secret" }),
    ).toThrow();
  });
  it("requires a genuine ZIP footer, exact completion comment, and complete transfer", () => {
    const footer = new Uint8Array(EXPORT_TAIL_BYTES);
    footer.set([0x50, 0x4b, 5, 6]);
    footer[20] = EXPORT_COMPLETE.length;
    footer.set(new TextEncoder().encode(EXPORT_COMPLETE), 22);
    expect(hasCompleteExport(footer)).toBe(true);
    for (let i = 0; i < footer.length; i++)
      expect(hasCompleteExport(footer.slice(0, i))).toBe(false);
    let tail: Uint8Array = new Uint8Array();
    for (const byte of footer)
      tail = appendExportTail(tail, new Uint8Array([byte]));
    expect(hasCompleteExport(tail)).toBe(true);
    expect(
      hasCompleteExport(appendExportTail(footer, new Uint8Array([0]))),
    ).toBe(false);
    footer[0] = 0;
    expect(hasCompleteExport(footer)).toBe(false);
  });
});

describe("review Markdown", () => {
  const review = {
    id,
    scope: "chapter",
    chapter_id: "00000000-0000-0000-0000-0000000000c1",
    review_year: null,
    model: "claude-sonnet-5-5",
    generated_at: "2026-10-18T12:00:00+00:00",
    entries_read: 6,
    entries_in_period: 6,
    content: {
      summary: "A tense spring that settled.",
      feelings: {
        overview: "Mostly steady.",
        phases: [
          {
            feeling: "Anxious",
            description: "Waiting on answers.",
            entryIds: ["e1", "e2"],
            windowStart: "2026-03-05",
            windowEnd: "2026-04-01",
          },
        ],
      },
      themes: [
        { name: "Work", description: "It came up often.", entryIds: ["e1"] },
      ],
      quotes: [
        {
          entryId: "e1",
          start: 0,
          end: 10,
          text: "First line\nSecond line",
          why: "It says it plainly.",
        },
      ],
    },
  };

  it("writes the labeled record with exact quotes and links to the Entries", () => {
    const markdown = reviewMarkdown(review, "Job search")!;
    expect(markdown).toContain('scope: "chapter"');
    expect(markdown).toContain("review_year: null");
    expect(markdown).toContain("# Review of Job search");
    expect(markdown).toContain(
      "> Written by Claude at your request. This is AI interpretation, not your own writing. Quotes are copied exactly from your Entries.",
    );
    expect(markdown).toContain("A tense spring that settled.");
    expect(markdown).toContain("## How it felt");
    expect(markdown).toContain("Entries dated 2026-03-05 to 2026-03-31.");
    expect(markdown).toContain("## What kept coming back");
    expect(markdown).toContain(
      "## In your words\n\n> First line\n> Second line\n>\n> From entries/e1.md",
    );
    expect(markdown).toContain("Why it stands out: It says it plainly.");
  });

  it("names a year review by its year and skips a row without a review", () => {
    expect(
      reviewMarkdown({ ...review, scope: "year", review_year: 2025 }, null),
    ).toContain("# Review of 2025");
    expect(reviewMarkdown({ ...review, content: null }, null)).toBeNull();
    expect(
      reviewMarkdown({ ...review, content: { summary: 3 } }, null),
    ).toBeNull();
  });
});
