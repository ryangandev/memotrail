import { describe, expect, it } from "vitest";
import { buildZip, tinyPng } from "./test-zip";
import {
  ImportError,
  ZipArchive,
  bufferSource,
  looksLikeZip,
  type RangeSource,
} from "./zip";

describe("ZipArchive", () => {
  it("lists members and skips macOS and system files", async () => {
    const zip = await buildZip({
      "Notes/one.md": "# One",
      "Notes/two.md": "Two",
      "__MACOSX/Notes/._one.md": "junk",
      "Notes/.DS_Store": "junk",
      "Notes/Thumbs.db": "junk",
      "Notes/._two.md": "junk",
    });
    const archive = await ZipArchive.open(zip);
    expect(archive.members.map((member) => member.path).sort()).toEqual([
      "Notes/one.md",
      "Notes/two.md",
    ]);
    archive.close();
  });

  it("reads text, strips a byte order mark, and normalizes names", async () => {
    const zip = await buildZip({
      "café.md": "﻿Hello",
    });
    const archive = await ZipArchive.open(zip);
    const member = archive.find("café.md");
    expect(member?.path).toBe("café.md");
    expect(await archive.readText(member!, 1000)).toBe("Hello");
    archive.close();
  });

  it("refuses to read more than the cap", async () => {
    const zip = await buildZip({ "big.md": "x".repeat(2000) });
    const archive = await ZipArchive.open(zip);
    await expect(
      archive.readBuffer(archive.find("big.md")!, 1000),
    ).rejects.toMatchObject({ code: "file_too_large" });
    archive.close();
  });

  it("reads through ranged reads and only the blocks it needs", async () => {
    const files: Record<string, string> = {};
    for (let i = 0; i < 50; i += 1)
      files[`n/${i}.md`] = `note ${i} `.repeat(20);
    const bytes = await buildZip({ ...files, "photo.png": tinyPng });
    const calls: [number, number][] = [];
    const source: RangeSource = {
      size: bytes.length,
      read: async (start, end) => {
        calls.push([start, end]);
        return bytes.subarray(start, end);
      },
    };
    const archive = await ZipArchive.open(source);
    expect(archive.members).toHaveLength(51);
    const text = await archive.readText(archive.find("n/7.md")!, 10_000);
    expect(text.startsWith("note 7 ")).toBe(true);
    expect(await archive.readBuffer(archive.find("photo.png")!, 1000)).toEqual(
      tinyPng,
    );
    // The archive is far below one block, so one ranged read serves everything.
    expect(calls).toHaveLength(1);
    archive.close();
  });

  it("returns the head of a member without reading the rest", async () => {
    const zip = await buildZip({ "a.bin": Buffer.alloc(100_000, 7) });
    const archive = await ZipArchive.open(zip);
    const head = await archive.readHead(archive.find("a.bin")!, 8);
    expect(head).toEqual(Buffer.alloc(8, 7));
    archive.close();
  });

  it("opens a ZIP of part ZIPs one level deep", async () => {
    const part1 = await buildZip({
      "Page aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.md": "# A",
    });
    const part2 = await buildZip({
      "Page bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.md": "# B",
    });
    const zip = await buildZip({
      "Export-Part-1.zip": part1,
      "Export-Part-2.zip": part2,
    });
    const archive = await ZipArchive.open(zip);
    expect(
      archive.members.map((member) => [member.container, member.path]),
    ).toEqual([
      ["Export-Part-1.zip", "Page aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.md"],
      ["Export-Part-2.zip", "Page bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.md"],
    ]);
    const member = archive.find(
      "Page bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.md",
      "Export-Part-2.zip",
    );
    expect(await archive.readText(member!, 1000)).toBe("# B");
    archive.close();
  });

  it("leaves a ZIP attachment inside a notes export alone", async () => {
    const attachment = await buildZip({ "inner.md": "inside" });
    const zip = await buildZip({
      "notes.md": "text",
      "backup.zip": attachment,
    });
    const archive = await ZipArchive.open(zip);
    expect(archive.members.map((member) => member.path).sort()).toEqual([
      "backup.zip",
      "notes.md",
    ]);
    archive.close();
  });

  it("rejects something that is not a ZIP", async () => {
    await expect(
      ZipArchive.open(bufferSource(Buffer.from("not a zip at all, just text"))),
    ).rejects.toBeInstanceOf(ImportError);
  });

  it("recognizes the ZIP signature", () => {
    expect(looksLikeZip(Buffer.from([0x50, 0x4b, 0x03, 0x04]))).toBe(true);
    expect(looksLikeZip(Buffer.from("%PDF"))).toBe(false);
  });
});
