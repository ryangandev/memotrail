import { describe, expect, it } from "vitest";
import { plainTextFromDocument } from "@/lib/data/rich-text";
import { buildZip, tinyPng } from "../test-zip";
import type { ImportCandidate } from "../types";
import { ZipArchive } from "../zip";
import { appleJournalAdapter } from "./apple-journal";
import type { ScanItem } from "./shared";

// The export's markup is not documented. These pages are synthetic, shaped after what
// third-party importers describe, and the adapter is expected to degrade, not to match exactly.

async function scan(files: Record<string, string | Buffer>) {
  const archive = await ZipArchive.open(await buildZip(files));
  const items: ScanItem[] = [];
  for await (const item of appleJournalAdapter.scan(archive, {
    source: "apple_journal",
  }))
    items.push(item);
  const detected = appleJournalAdapter.detect(archive);
  archive.close();
  return { detected, items };
}

const entries = (items: ScanItem[]) =>
  items.flatMap((item) => (item.kind === "entry" ? [item.candidate] : []));
const text = (candidate: ImportCandidate) =>
  plainTextFromDocument(candidate.bodyRich);

const page = (inner: string) =>
  `<html><head><title>Entry</title><style>.p1{margin:0}</style></head><body>${inner}</body></html>`;

describe("Apple Journal adapter", () => {
  it("reads the date, title, writing, and a photo from a page", async () => {
    const { items, detected } = await scan({
      "AppleJournalEntries/Entries/2024-05-12_Beach.html": page(`
        <div class="pageHeader">Sunday, May 12, 2024</div>
        <div class="title">Beach day</div>
        <div class="bodyText"><p class="p1"><span>We swam <b>all</b> afternoon.</span></p></div>
        <div class="assetGrid"><img src="../Resources/ABC.png" alt=""></div>`),
      "AppleJournalEntries/Resources/ABC.png": tinyPng,
    });
    expect(detected).toBeGreaterThanOrEqual(0.9);
    const [entry] = entries(items);
    expect(entry.title).toBe("Beach day");
    expect(entry.date).toEqual({ local: "2024-05-12", precision: "day" });
    expect(text(entry)).toBe("We swam all afternoon.");
    expect(entry.photos.map((photo) => photo.originalFilename)).toEqual([
      "ABC.png",
    ]);
    expect(entry.sourceKey).toBe("entry:2024-05-12_beach.html");
  });

  it("keeps a time when the date shows one", async () => {
    const { items } = await scan({
      "Entries/a.html": page(
        `<div class="pageHeader">Sunday, May 12, 2024 at 3:45 PM</div><div class="bodyText"><p>Hi</p></div>`,
      ),
    });
    const [entry] = entries(items);
    expect(entry.date).toMatchObject({ precision: "exact" });
  });

  it("appends State of Mind and place lines as plain text", async () => {
    const { items } = await scan({
      "Entries/a.html": page(`
        <div class="pageHeader">May 12, 2024</div>
        <div class="bodyText"><p>Quiet morning.</p></div>
        <div class="stateOfMind">Slightly Pleasant</div>
        <div class="location">Lisbon, Portugal</div>`),
    });
    const [entry] = entries(items);
    expect(text(entry)).toContain("Quiet morning.");
    expect(text(entry)).toContain("Slightly Pleasant");
    expect(text(entry)).toContain("Lisbon, Portugal");
  });

  it("leaves a map picture out and counts videos as not imported", async () => {
    const { items } = await scan({
      "Entries/a.html": page(`
        <div class="pageHeader">May 12, 2024</div>
        <div class="bodyText"><p>Out.</p></div>
        <img class="mapSnapshot" src="../Resources/map.png">
        <video src="../Resources/clip.mov"></video>`),
      "Resources/map.png": tinyPng,
    });
    const [entry] = entries(items);
    expect(entry.photos).toHaveLength(0);
    expect(entry.skippedResources).toContainEqual({ count: 1, kind: "map" });
    expect(entry.skippedResources).toContainEqual({ count: 1, kind: "video" });
  });

  it("degrades to the page text when the markup has no known classes", async () => {
    const { items } = await scan({
      "Entries/2024-05-12.html": page(
        `<h1>Plain page</h1><p>Some words here.</p>`,
      ),
    });
    const [entry] = entries(items);
    expect(text(entry)).toContain("Some words here.");
    // The file name still dates it.
    expect(entry.date).toEqual({ local: "2024-05-12", precision: "day" });
  });

  it("keeps an unreadable date as text, undated, with a warning", async () => {
    const { items } = await scan({
      "Entries/x.html": page(
        `<div class="pageHeader">dimanche 12 mai 2024</div><div class="bodyText"><p>Bonjour.</p></div>`,
      ),
    });
    const [entry] = entries(items);
    expect(entry.date).toEqual({
      label: "dimanche 12 mai 2024",
      precision: "unknown",
    });
    expect(entry.warnings).toContain("date_unparsed");
  });

  it("does not treat other HTML files as entries", async () => {
    const { items, detected } = await scan({
      "index.html": page("<p>Index</p>"),
    });
    expect(items).toEqual([]);
    expect(detected).toBe(0);
  });
});
