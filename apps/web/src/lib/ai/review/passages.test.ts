import { describe, expect, it } from "vitest";
import { codePointLength, segmentPassages } from "./passages";

const slice = (body: string, start: number, end: number) =>
  Array.from(body).slice(start, end).join("");

function expectExactOffsets(body: string) {
  const passages = segmentPassages(body);
  for (const passage of passages) {
    expect(slice(body, passage.start, passage.end)).toBe(passage.text);
    expect(passage.text).toBe(passage.text.trim());
    expect(passage.text.length).toBeGreaterThan(0);
  }
  expect(passages.map((passage) => passage.id)).toEqual(
    passages.map((_, index) => index + 1),
  );
  return passages;
}

describe("segmentPassages", () => {
  it("splits English into sentences and keeps offsets exact", () => {
    const body =
      "I went to the first interview today. It was nerve-racking at first.\nThe second one felt much easier.";
    const passages = expectExactOffsets(body);
    expect(passages.map((passage) => passage.text)).toEqual([
      "I went to the first interview today.",
      "It was nerve-racking at first.",
      "The second one felt much easier.",
    ]);
  });

  it("splits Chinese on full-width sentence marks", () => {
    const body = "今天去了第一次面试，感觉很紧张。后来慢慢放松了！你觉得呢？";
    const passages = expectExactOffsets(body);
    expect(passages.length).toBeGreaterThanOrEqual(2);
    expect(passages[0].text.endsWith("。")).toBe(true);
  });

  it("handles mixed text", () => {
    const body =
      "今天 I started the new job。It felt like 重新开始. Good day overall.";
    expectExactOffsets(body);
  });

  it("counts offsets in code points for emoji and other astral characters", () => {
    const body =
      "We hiked the ridge 🥾 and it was great. 𠮷野家 for dinner was better than expected.";
    const passages = expectExactOffsets(body);
    expect(codePointLength(body)).toBeLessThan(body.length);
    const last = passages[passages.length - 1];
    expect(last.end).toBe(codePointLength(body));
  });

  it("trims surrounding whitespace by moving offsets, never by changing text", () => {
    const body = "   First sentence here.   \n\n   Second sentence there.  ";
    const passages = expectExactOffsets(body);
    expect(passages.map((passage) => passage.text)).toEqual([
      "First sentence here.",
      "Second sentence there.",
    ]);
    expect(passages[0].start).toBe(3);
  });

  it("merges very short pieces into the next one in the paragraph", () => {
    const body = "Okay. Today I finally finished the long report for work.";
    const passages = expectExactOffsets(body);
    expect(passages).toHaveLength(1);
    expect(passages[0].text).toBe(body);
  });

  it("joins a short last piece to the previous one", () => {
    const body = "We spent the whole afternoon walking by the water. Wow.";
    const passages = expectExactOffsets(body);
    expect(passages).toHaveLength(1);
  });

  it("keeps a short paragraph on its own", () => {
    const body =
      "A long first paragraph with real words in it.\nHi.\nAnother long paragraph with real words in it.";
    const passages = expectExactOffsets(body);
    expect(passages.map((passage) => passage.text)).toContain("Hi.");
  });

  it("splits a very long sentence at a comma or space before 300 code points", () => {
    const clause = "and then we kept going because the weather was holding";
    const body = `${Array.from({ length: 20 }, () => clause).join(", ")}.`;
    expect(codePointLength(body)).toBeGreaterThan(1000);
    const passages = expectExactOffsets(body);
    expect(passages.length).toBeGreaterThan(2);
    for (const passage of passages)
      expect(passage.end - passage.start).toBeLessThanOrEqual(400);
  });

  it("splits a long run with no break at 300 code points", () => {
    const body = "字".repeat(1000);
    const passages = expectExactOffsets(body);
    expect(passages.map((passage) => passage.end - passage.start)).toEqual([
      300, 300, 400,
    ]);
  });

  it("returns nothing for blank text", () => {
    expect(segmentPassages("")).toEqual([]);
    expect(segmentPassages(" \n\n \n")).toEqual([]);
  });
});
