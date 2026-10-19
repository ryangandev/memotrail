import { describe, expect, it } from "vitest";
import { scanArchive, type ScanRow } from "./scan";
import { buildZip, tinyPng } from "./test-zip";
import { ImportError, ZipArchive } from "./zip";

async function scan(files: Record<string, string | Buffer>) {
  const archive = await ZipArchive.open(await buildZip(files));
  const stored: ScanRow[] = [];
  const seen = new Set<string>();
  try {
    const totals = await scanArchive(
      archive,
      { source: "markdown", timezone: "America/New_York" },
      {
        async add(rows) {
          let added = 0;
          for (const row of rows) {
            if (seen.has(row.source_key)) continue;
            seen.add(row.source_key);
            stored.push(row);
            added += 1;
          }
          return added;
        },
      },
    );
    return { stored, totals };
  } finally {
    archive.close();
  }
}

describe("scanArchive", () => {
  it("counts entries, photos, dates, and folders for the preview", async () => {
    const { totals, stored } = await scan({
      "Trips/Rome/a.md": "---\ndate: 2024-05-12\n---\nPasta.\n\n![](pic.png)",
      "Trips/Rome/pic.png": tinyPng,
      "Trips/b.md": "---\ndate: 2023-01-02\n---\nSnow.",
      "c.md": "No date here.",
    });
    expect(totals.entries).toBe(3);
    expect(totals.photos).toBe(1);
    expect(totals.undated).toBe(1);
    expect(totals.dateRange).toEqual({ from: "2023-01-02", to: "2024-05-12" });
    expect(totals.distinctParentFolders).toBe(2);
    expect(totals.folders.map((folder) => folder.path.join("/"))).toEqual([
      "Trips",
      "Trips/Rome",
    ]);
    expect(
      totals.folders.find((f) => f.path.join("/") === "Trips")?.entries,
    ).toBe(2);
    expect(stored.every((row) => row.status === "pending")).toBe(true);
  });

  it("stores the photos in media and keeps the payload free of them", async () => {
    const { stored } = await scan({
      "a.md": "Hello\n\n![](pic.png)",
      "pic.png": tinyPng,
    });
    const [row] = stored;
    expect(row.media?.photos).toHaveLength(1);
    expect(row.media?.photos[0].status).toBe("pending");
    expect(row.payload).not.toHaveProperty("photos");
    expect(row.content_hash).toMatch(/^[0-9a-f]{64}$/);
  });

  it("refuses an archive with nothing to import", async () => {
    await expect(scan({ "readme.txt": "not a note" })).rejects.toMatchObject({
      code: "empty_import",
    });
    await expect(scan({ "readme.txt": "x" })).rejects.toBeInstanceOf(
      ImportError,
    );
  });

  it("counts a repeated source key once", async () => {
    // Two notes with the same relative name cannot exist in one folder, so repeat across the sink.
    const archive = await ZipArchive.open(await buildZip({ "a.md": "One." }));
    let calls = 0;
    const totals = await scanArchive(
      archive,
      { source: "markdown", timezone: "UTC" },
      {
        async add(rows) {
          calls += 1;
          return rows.length - 1;
        },
      },
    );
    archive.close();
    expect(calls).toBe(1);
    expect(totals.duplicateKeys).toBe(1);
  });
});
