import { describe, expect, it } from "vitest";
import { plainTextFromDocument } from "@/lib/data/rich-text";
import { buildZip, tinyPng } from "../test-zip";
import { ZipArchive } from "../zip";
import { dayOneAdapter } from "./day-one";
import type { ScanItem } from "./shared";

async function scan(files: Record<string, string | Buffer>) {
  const archive = await ZipArchive.open(await buildZip(files));
  const items: ScanItem[] = [];
  for await (const item of dayOneAdapter.scan(archive, { source: "day_one" }))
    items.push(item);
  const detected = dayOneAdapter.detect(archive);
  archive.close();
  return { detected, items };
}

const entries = (items: ScanItem[]) =>
  items.flatMap((item) => (item.kind === "entry" ? [item.candidate] : []));

function journal(list: unknown[]) {
  return JSON.stringify({ entries: list, metadata: { version: "1.0" } });
}

describe("Day One adapter", () => {
  it("maps the exact time, time zone, tags, place, and key", async () => {
    const { items, detected } = await scan({
      "Journal.json": journal([
        {
          creationDate: "2024-05-12T14:03:00Z",
          location: {
            country: "Portugal",
            localityName: "Lisbon",
            placeName: "Time Out Market",
          },
          modifiedDate: "2024-05-13T08:00:00Z",
          tags: ["travel", "food"],
          text: "# Lisbon day\n\nCustard tarts\\. Very good\\.",
          timeZone: "Europe/Lisbon",
          uuid: "AAAA1111",
        },
      ]),
      "photos/.keep": "",
    });
    expect(detected).toBeGreaterThanOrEqual(0.8);
    const [note] = entries(items);
    expect(note.sourceKey).toBe("AAAA1111");
    expect(note.title).toBe("Lisbon day");
    expect(plainTextFromDocument(note.bodyRich)).toBe(
      "Custard tarts. Very good.",
    );
    expect(note.date).toEqual({
      instant: "2024-05-12T14:03:00.000Z",
      precision: "exact",
      timezone: "Europe/Lisbon",
    });
    expect(note.tagNames).toEqual(["travel", "food"]);
    expect(note.locationLabel).toBe("Time Out Market, Lisbon, Portugal");
    expect(note.sourceModifiedAt).toBe("2024-05-13T08:00:00.000Z");
  });

  it("leaves an entry without a heading untitled", async () => {
    const { items } = await scan({
      "Journal.json": journal([
        {
          creationDate: "2024-01-01T10:00:00Z",
          text: "Just a few words.",
          uuid: "B1",
        },
      ]),
    });
    expect(entries(items)[0].title).toBeNull();
  });

  it("attaches photos by checksum, in the order the writing shows them", async () => {
    const { items } = await scan({
      "Journal.json": journal([
        {
          creationDate: "2024-01-01T10:00:00Z",
          photos: [
            { identifier: "P1", md5: "aaa", type: "jpeg" },
            { identifier: "P2", md5: "bbb", type: "png" },
          ],
          text: "First ![](dayone-moment://P2) then ![](dayone-moment://P1)",
          uuid: "C1",
        },
      ]),
      "photos/aaa.jpeg": tinyPng,
      "photos/bbb.png": tinyPng,
    });
    const [note] = entries(items);
    expect(note.photos.map((photo) => photo.originalFilename)).toEqual([
      "bbb.png",
      "aaa.jpeg",
    ]);
    expect(plainTextFromDocument(note.bodyRich)).not.toContain("dayone-moment");
  });

  it("warns about a photo file that is missing and counts videos as skipped", async () => {
    const { items } = await scan({
      "Journal.json": journal([
        {
          creationDate: "2024-01-01T10:00:00Z",
          photos: [{ identifier: "P1", md5: "zzz", type: "jpeg" }],
          text: "Words ![](dayone-moment://P1) ![](dayone-moment:/video/V1)",
          uuid: "D1",
          videos: [{ identifier: "V1" }],
        },
      ]),
    });
    const [note] = entries(items);
    expect(note.photos).toHaveLength(0);
    expect(note.warnings).toContain("photo_missing");
    expect(note.skippedResources).toContainEqual({ count: 1, kind: "video" });
  });

  it("keeps a photo-only entry and skips an empty one", async () => {
    const { items } = await scan({
      "Journal.json": journal([
        {
          creationDate: "2024-01-01T10:00:00Z",
          photos: [{ identifier: "P1", md5: "aaa", type: "png" }],
          text: "![](dayone-moment://P1)",
          uuid: "E1",
        },
        { creationDate: "2024-01-02T10:00:00Z", text: "", uuid: "E2" },
      ]),
      "photos/aaa.png": tinyPng,
    });
    expect(entries(items)).toHaveLength(1);
    expect(items.find((item) => item.kind === "skipped")).toMatchObject({
      reason: "empty",
      sourceKey: "E2",
    });
  });

  it("uses one folder per journal when an export holds several", async () => {
    const { items } = await scan({
      "Journal.json": journal([
        { creationDate: "2024-01-01T10:00:00Z", text: "One", uuid: "F1" },
      ]),
      "Work.json": journal([
        { creationDate: "2024-01-01T11:00:00Z", text: "Two", uuid: "F2" },
      ]),
    });
    expect(entries(items).map((note) => note.folderPath)).toEqual([
      ["Journal"],
      ["Work"],
    ]);
  });

  it("is not fooled by a JSON file that is not a journal", async () => {
    const { items, detected } = await scan({
      "other.json": JSON.stringify({ hello: "world" }),
    });
    expect(items).toEqual([]);
    expect(detected).toBeLessThan(0.7);
  });

  it("marks an entry with no readable time as undated", async () => {
    const { items } = await scan({
      "Journal.json": journal([{ text: "No time", uuid: "G1" }]),
    });
    const [note] = entries(items);
    expect(note.date).toEqual({ precision: "unknown" });
    expect(note.warnings).toContain("date_unparsed");
  });
});
