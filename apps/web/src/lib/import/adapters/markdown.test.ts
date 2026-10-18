import { describe, expect, it } from "vitest";
import { plainTextFromDocument } from "@/lib/data/rich-text";
import { buildZip, tinyPng } from "../test-zip";
import type { ImportCandidate } from "../types";
import { ZipArchive } from "../zip";
import { markdownAdapter } from "./markdown";
import type { ScanItem } from "./shared";

async function scan(
  files: Record<string, string | Buffer>,
  source: "markdown" | "apple_notes" = "markdown",
) {
  const archive = await ZipArchive.open(await buildZip(files));
  const items: ScanItem[] = [];
  for await (const item of markdownAdapter.scan(archive, { source }))
    items.push(item);
  archive.close();
  return items;
}

const entries = (items: ScanItem[]) =>
  items.flatMap((item) => (item.kind === "entry" ? [item.candidate] : []));
const text = (candidate: ImportCandidate) =>
  plainTextFromDocument(candidate.bodyRich);

describe("Markdown adapter", () => {
  it("reads frontmatter date and tags, and inline tags", async () => {
    const [note] = entries(
      await scan({
        "Vault/Trip.md": [
          "---",
          "title: Lisbon trip",
          "date: 2024-05-12",
          "tags: [travel, Food]",
          "---",
          "We ate pastries. #custard and #travel again.",
        ].join("\n"),
      }),
    );
    expect(note.title).toBe("Lisbon trip");
    expect(note.date).toEqual({ local: "2024-05-12", precision: "day" });
    expect(note.tagNames).toEqual(["travel", "Food", "custard", "travel"]);
    expect(text(note)).toContain("We ate pastries.");
    expect(note.sourceKey).toBe("Trip.md");
  });

  it("uses a first line heading as the title and does not repeat it", async () => {
    const [note] = entries(
      await scan({ "a.md": "# Morning pages\n\nWrote for an hour." }),
    );
    expect(note.title).toBe("Morning pages");
    expect(text(note)).toBe("Wrote for an hour.");
  });

  it("turns a title that is only a date into the date", async () => {
    const [note] = entries(await scan({ "May 12, 2024.md": "Rainy day." }));
    expect(note.title).toBeNull();
    expect(note.date).toEqual({ local: "2024-05-12", precision: "day" });
  });

  it("takes the date from the file name when nothing else has one", async () => {
    const [note] = entries(await scan({ "2023-01-05 Lunch.md": "Soup." }));
    expect(note.title).toBe("2023-01-05 Lunch");
    expect(note.date).toEqual({ local: "2023-01-05", precision: "day" });
  });

  it("leaves a note with no date unknown and keeps the raw text of one it cannot read", async () => {
    const items = entries(
      await scan({
        "plain.md": "Hello",
        "odd.md": "---\ndate: sometime last spring\n---\nHi",
      }),
    );
    const odd = items.find((item) => item.sourceKey === "odd.md")!;
    expect(odd.date).toEqual({ label: "sometime last spring", precision: "unknown" });
    expect(odd.warnings).toContain("date_unparsed");
    expect(items.find((item) => item.sourceKey === "plain.md")!.date.precision).toBe(
      "unknown",
    );
  });

  it("flattens wikilinks and collects pictures from both syntaxes", async () => {
    const [note] = entries(
      await scan({
        "Notes/Day.md": "See [[Other note|my friend]] and [[Plain]].\n\n![[pic one.png]]\n\n![Sunset over the bay with boats](../Assets/sun%20set.png)",
        "Assets/sun set.png": tinyPng,
        "Notes/pic one.png": tinyPng,
      }),
    );
    expect(text(note)).toBe(
      "See my friend and Plain.\nSunset over the bay with boats",
    );
    expect(note.photos.map((photo) => photo.zipPath)).toEqual([
      "Notes/pic one.png",
      "Assets/sun set.png",
    ]);
    expect(note.folderPath).toEqual(["Notes"]);
  });

  it("counts videos and other files as not imported and keeps external pictures as links", async () => {
    const [note] = entries(
      await scan({
        "a.md": "![clip](clip.mov)\n\n![](https://example.com/x.png)\n\n![doc](file.pdf)",
        "clip.mov": "x",
        "file.pdf": "x",
      }),
    );
    expect(note.skippedResources).toEqual(
      expect.arrayContaining([
        { count: 1, kind: "video" },
        { count: 1, kind: "pdf" },
      ]),
    );
    expect(note.photos).toHaveLength(0);
  });

  it("splits a very long body into parts with their own keys", async () => {
    const paragraphs = Array.from({ length: 60 }, (_, i) => `Paragraph ${i}. ${"word ".repeat(200)}`);
    const items = entries(
      await scan({ "long.md": `# Long one\n\n${paragraphs.join("\n\n")}` }),
    );
    expect(items.length).toBeGreaterThan(1);
    expect(items.map((item) => item.sourceKey)).toEqual(
      items.map((_, i) => (i === 0 ? "long.md" : `long.md#${i + 1}`)),
    );
    expect(items[0].title).toBe(`Long one (1/${items.length})`);
    for (const item of items) expect(text(item).length).toBeLessThanOrEqual(50_000);
  });

  it("skips an empty note and keeps a photo-only note", async () => {
    const items = await scan({
      "empty.md": "   \n",
      "photo.md": "![](p.png)",
      "p.png": tinyPng,
    });
    expect(items.find((item) => item.kind === "skipped")).toMatchObject({
      reason: "empty",
      sourceKey: "empty.md",
    });
    const [photo] = entries(items);
    expect(photo.photos).toHaveLength(1);
    expect(photo.title).toBe("photo");
  });

  it("keys Apple Notes by content and Markdown by an explicit id when there is one", async () => {
    const notes = entries(
      await scan(
        { "Recipes/Soup.md": "# Soup\n\nBoil water." },
        "apple_notes",
      ),
    );
    expect(notes[0].sourceKey).toMatch(/^note:[a-f0-9]{32}$/);
    expect(notes[0].folderPath).toEqual(["Recipes"]);
    const withId = entries(await scan({ "x.md": "---\nid: abc-1\n---\nBody" }));
    expect(withId[0].sourceKey).toBe("id:abc-1");
  });

  it("degrades headings, tables, and unsafe links to what the Entry can hold", async () => {
    const [note] = entries(
      await scan({
        "a.md": [
          "## Plan",
          "",
          "| a | b |",
          "| - | - |",
          "| 1 | 2 |",
          "",
          "[bad](javascript:alert(1)) and [good](https://example.com)",
          "",
          "<script>alert(1)</script><b>bold html</b>",
        ].join("\n"),
      }),
    );
    expect(note.bodyRich.content[0]).toMatchObject({
      content: [{ marks: [{ type: "bold" }], text: "Plan", type: "text" }],
      type: "paragraph",
    });
    const body = text(note);
    expect(body).toContain("a\tb");
    expect(body).toContain("bad and good");
    expect(body).not.toContain("alert");
    expect(JSON.stringify(note.bodyRich)).not.toContain("javascript:");
    expect(JSON.stringify(note.bodyRich)).toContain("https://example.com");
  });
});
