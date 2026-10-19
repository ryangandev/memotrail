import { describe, expect, it } from "vitest";
import { plainTextFromDocument } from "@/lib/data/rich-text";
import { dateWithProperty } from "../dates";
import { scanArchive, type ScanRow } from "../scan";
import { buildZip, tinyPng } from "../test-zip";
import type { ImportCandidate } from "../types";
import { ZipArchive } from "../zip";
import { notionAdapter, splitNotionName, splitProperties } from "./notion";
import type { ScanItem } from "./shared";

const idA = "a1b2c3d4e5f60718293a4b5c6d7e8f90";
const idB = "b1b2c3d4e5f60718293a4b5c6d7e8f91";
const idC = "c1b2c3d4e5f60718293a4b5c6d7e8f92";
const idD = "d1b2c3d4e5f60718293a4b5c6d7e8f93";

async function scan(files: Record<string, string | Buffer>) {
  const archive = await ZipArchive.open(await buildZip(files));
  const items: ScanItem[] = [];
  for await (const item of notionAdapter.scan(archive, { source: "notion" }))
    items.push(item);
  const detected = notionAdapter.detect(archive);
  archive.close();
  return { detected, items };
}

const entries = (items: ScanItem[]) =>
  items.flatMap((item) => (item.kind === "entry" ? [item.candidate] : []));
const text = (candidate: ImportCandidate) =>
  plainTextFromDocument(candidate.bodyRich);

describe("splitNotionName", () => {
  it("separates the trailing id from the title", () => {
    expect(splitNotionName(`Trip to Rome ${idA}`)).toEqual({
      id: idA,
      title: "Trip to Rome",
    });
    expect(splitNotionName("Plain name")).toEqual({
      id: null,
      title: "Plain name",
    });
  });
});

describe("splitProperties", () => {
  it("takes the block of Key: value lines under the heading", () => {
    const result = splitProperties(
      "# Task\n\nStatus: Done\nDate: October 18, 2026\n\nBody text.",
    );
    expect(result.heading).toBe("Task");
    expect(result.properties).toEqual([
      ["Status", "Done"],
      ["Date", "October 18, 2026"],
    ]);
    expect(result.rest.trim()).toBe("Body text.");
  });

  it("leaves a paragraph alone when any line is not a property", () => {
    const result = splitProperties(
      "# Task\n\nStatus: Done\nand then some prose\n\nMore.",
    );
    expect(result.properties).toEqual([]);
  });
});

describe("Notion adapter", () => {
  it("uses the id as the key, strips ids from folders, and reads pictures", async () => {
    const { items, detected } = await scan({
      [`Projects ${idA}/Rome ${idB}.md`]:
        "# Rome\n\nPasta.\n\n![Pic](Rome/pic.png)",
      [`Projects ${idA}/Rome/pic.png`]: tinyPng,
    });
    expect(detected).toBeGreaterThanOrEqual(0.9);
    const [page] = entries(items);
    expect(page.sourceKey).toBe(idB);
    expect(page.title).toBe("Rome");
    expect(page.folderPath).toEqual(["Projects"]);
    expect(page.photos.map((photo) => photo.originalFilename)).toEqual([
      "pic.png",
    ]);
    expect(page.date).toEqual({ precision: "unknown" });
  });

  it("falls back to the file name for the title and leaves external images as links", async () => {
    const { items } = await scan({
      [`Idea ${idA}.md`]: "A thought.\n\n![Remote](https://example.com/p.png)",
    });
    const [page] = entries(items);
    expect(page.title).toBe("Idea");
    expect(text(page)).toContain("Remote");
    expect(page.photos).toHaveLength(0);
  });

  it("reads database row properties for date and tags, and keeps them in the text", async () => {
    const { items } = await scan({
      [`Reading ${idA}.csv`]: "Name,Date\nBook,2026-10-18\n",
      [`Reading/Book ${idB}.md`]: [
        "# Book",
        "",
        "Status: Done",
        "Date: October 18, 2026",
        "Tags: fiction, loved",
        "",
        "Great read.",
      ].join("\n"),
    });
    const [row] = entries(items);
    expect(row.dateProperties).toEqual({ Date: "October 18, 2026" });
    expect(row.propertyTagNames).toEqual(["fiction", "loved"]);
    expect(text(row)).toContain("Status: Done");
    expect(text(row)).toContain("Great read.");
    expect(row.folderPath).toEqual(["Reading"]);
    // The page itself carries no date until a property is chosen.
    expect(row.date).toEqual({ precision: "unknown" });
    expect(dateWithProperty(row.date, row.dateProperties, "Date")).toEqual({
      local: "2026-10-18",
      precision: "day",
    });
    expect(dateWithProperty(row.date, row.dateProperties, null)).toEqual(
      row.date,
    );
    expect(dateWithProperty(row.date, row.dateProperties, "Other")).toEqual(
      row.date,
    );
  });

  it("does not treat the top of an ordinary page as properties", async () => {
    const { items } = await scan({
      [`Recipe ${idA}.md`]:
        "# Recipe\n\nServes: four\nTime: one hour\n\nMix it.",
    });
    const [page] = entries(items);
    expect(page.dateProperties).toBeUndefined();
    expect(text(page)).toContain("Serves: four");
  });

  it("turns a callout into a quote", async () => {
    const { items } = await scan({
      [`Note ${idA}.md`]:
        "# Note\n\n<aside>\n💡 Remember the milk\n</aside>\n\nAfter.",
    });
    const [page] = entries(items);
    expect(
      page.bodyRich.content?.some((node) => node.type === "blockquote"),
    ).toBe(true);
    expect(text(page)).toContain("Remember the milk");
  });

  it("skips a page that only holds other pages", async () => {
    const { items } = await scan({
      [`Parent ${idA}.md`]: "# Parent\n",
      [`Parent ${idA}/Child ${idB}.md`]: "# Child\n\nReal words.",
    });
    expect(entries(items).map((page) => page.sourceKey)).toEqual([idB]);
    expect(items.find((item) => item.kind === "skipped")).toMatchObject({
      reason: "empty",
      sourceKey: idA,
    });
  });

  it("reads an export split into part ZIPs", async () => {
    const inner = await buildZip({
      [`Page ${idC}.md`]: "# Page\n\nInside a part.",
    });
    const { items } = await scan({ "Export-1234abcd-Part-1.zip": inner });
    expect(entries(items).map((page) => page.sourceKey)).toEqual([idC]);
  });

  it("offers the property that dates the most pages, and dates the totals with it", async () => {
    const archive = await ZipArchive.open(
      await buildZip({
        [`Log ${idA}.csv`]: "Name\n",
        [`Log/One ${idB}.md`]:
          "# One\n\nDate: 2026-01-05\nDue: 2026-02-01\n\nx",
        [`Log/Two ${idC}.md`]: "# Two\n\nDate: 2026-03-09\n\ny",
        [`Log/Three ${idD}.md`]: "# Three\n\nz",
      }),
    );
    const rows: ScanRow[] = [];
    const totals = await scanArchive(
      archive,
      { source: "notion", timezone: "UTC" },
      {
        async add(batch) {
          rows.push(...batch);
          return batch.length;
        },
      },
    );
    archive.close();
    expect(totals.entries).toBe(3);
    expect(totals.notionDateProperty).toBe("Date");
    expect(totals.notionDateProperties.sort()).toEqual(["Date", "Due"]);
    expect(totals.undated).toBe(1);
    expect(totals.dateRange).toEqual({ from: "2026-01-05", to: "2026-03-09" });
  });
});
