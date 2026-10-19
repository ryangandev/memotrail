import { describe, expect, it } from "vitest";
import {
  CHUNK_MAX_TOKENS,
  MAX_CHUNKS_PER_ENTRY,
  chunkEntryText,
} from "./chunking";

const slice = (body: string, start: number, end: number) =>
  Array.from(body).slice(start, end).join("");

function expectOffsetsToRoundTrip(body: string) {
  for (const chunk of chunkEntryText({ body, title: null })) {
    expect(slice(body, chunk.start, chunk.end)).toBe(chunk.text);
  }
}

function expectCoverage(body: string) {
  const chunks = chunkEntryText({ body, title: null });
  const covered = new Set<number>();
  for (const chunk of chunks) {
    for (let at = chunk.start; at < chunk.end; at += 1) covered.add(at);
  }
  Array.from(body).forEach((character, at) => {
    if (!/\s/u.test(character)) expect(covered.has(at)).toBe(true);
  });
}

describe("chunkEntryText", () => {
  it("keeps a short Entry as one chunk covering its writing", () => {
    expect(chunkEntryText({ body: "Rain all morning.", title: null })).toEqual([
      { end: 17, index: 0, start: 0, text: "Rain all morning." },
    ]);
  });

  it("trims whitespace from the range so a passage starts at its first word", () => {
    const [chunk] = chunkEntryText({ body: "\n  Hello there \n", title: null });
    expect(chunk).toMatchObject({ start: 3, end: 14, text: "Hello there" });
  });

  it("gives a title-only Entry one empty chunk", () => {
    expect(chunkEntryText({ body: "", title: "Dentist Thursday" })).toEqual([
      { end: 0, index: 0, start: 0, text: "" },
    ]);
    expect(chunkEntryText({ body: "  \n", title: "Dentist" })).toHaveLength(1);
  });

  it("gives an Entry with neither title nor writing no chunks", () => {
    expect(chunkEntryText({ body: "", title: null })).toEqual([]);
    expect(chunkEntryText({ body: " \n ", title: "  " })).toEqual([]);
  });

  it("splits long English text at paragraph breaks first", () => {
    const paragraph = (word: string) =>
      Array.from({ length: 120 }, () => word).join(" ") + ".";
    const body = [
      paragraph("alpha"),
      paragraph("beta"),
      paragraph("gamma"),
    ].join("\n\n");
    const chunks = chunkEntryText({ body, title: null });

    expect(chunks.length).toBeGreaterThan(1);
    for (const chunk of chunks.slice(0, -1)) {
      expect(body.slice(chunk.end, chunk.end + 2)).toMatch(/^\s|^$/);
    }
    expectOffsetsToRoundTrip(body);
    expectCoverage(body);
  });

  it("splits Chinese text at sentence ends and counts each character as a token", () => {
    const sentence = "今天在海边跑步，风很大，心情特别好。";
    const body = sentence.repeat(60);
    const chunks = chunkEntryText({ body, title: null });

    expect(chunks.length).toBeGreaterThan(2);
    for (const chunk of chunks) {
      expect(chunk.end - chunk.start).toBeLessThanOrEqual(CHUNK_MAX_TOKENS);
    }
    for (const chunk of chunks.slice(0, -1)) {
      expect(chunk.text.endsWith("。")).toBe(true);
    }
    expectOffsetsToRoundTrip(body);
    expectCoverage(body);
  });

  it("handles mixed English and Chinese", () => {
    const body =
      "We met at the climbing gym 然后去吃了火锅。 Afterwards we walked home. ".repeat(
        80,
      );
    const chunks = chunkEntryText({ body, title: null });

    expect(chunks.length).toBeGreaterThan(1);
    expectOffsetsToRoundTrip(body);
    expectCoverage(body);
  });

  it("overlaps consecutive chunks", () => {
    const body = Array.from({ length: 900 }, (_, at) => `word${at}`).join(" ");
    const chunks = chunkEntryText({ body, title: null });

    expect(chunks.length).toBeGreaterThan(2);
    chunks.slice(1).forEach((chunk, at) => {
      expect(chunk.start).toBeLessThan(chunks[at].end);
      expect(chunk.start).toBeGreaterThan(chunks[at].start);
    });
  });

  it("counts offsets in code points, not UTF-16 units", () => {
    const body = "😀 emoji and 𠀀 rare Han text. ".repeat(120);
    const chunks = chunkEntryText({ body, title: null });

    expect(chunks.length).toBeGreaterThan(1);
    expectOffsetsToRoundTrip(body);
    expect(chunks.at(-1)?.end).toBeLessThanOrEqual(Array.from(body).length);
  });

  it("cuts text with no boundaries at the target size", () => {
    const body = "x".repeat(6000);
    const chunks = chunkEntryText({ body, title: null });

    expect(chunks.length).toBeGreaterThan(1);
    expectCoverage(body);
  });

  it("never exceeds the chunk limit, even for the longest allowed Entry", () => {
    const body = "好".repeat(50_000);
    const chunks = chunkEntryText({ body, title: null });

    expect(chunks.length).toBeLessThanOrEqual(MAX_CHUNKS_PER_ENTRY);
    expect(chunks.map((chunk) => chunk.index)).toEqual(
      chunks.map((_, at) => at),
    );
    expect(chunks.at(-1)?.end).toBe(50_000);
    expectOffsetsToRoundTrip(body);
  });
});
