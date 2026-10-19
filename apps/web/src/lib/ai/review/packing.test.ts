import { describe, expect, it } from "vitest";
import {
  estimateJobMicros,
  estimateTokens,
  MAX_SEGMENTS,
  packPeriod,
  REDUCE_INPUT_TOKENS,
  SEGMENT_TOKENS,
  SINGLE_PASS_TOKENS,
  sentPassages,
  TRIM_CODE_POINTS,
  type PackableEntry,
} from "./packing";

let counter = 0;
function entry(
  overrides: Partial<PackableEntry> & { words?: number } = {},
): PackableEntry {
  counter += 1;
  const { words = 20, ...rest } = overrides;
  const sentence = "This is a plain sentence about my day and what happened.";
  return {
    id: `e${String(counter).padStart(4, "0")}`,
    isSubject: false,
    title: "",
    body: Array.from(
      { length: Math.max(1, Math.round(words / 10)) },
      () => sentence,
    ).join(" "),
    tags: [],
    isFirstTime: false,
    ...rest,
  };
}

const lineOf = (i: number) =>
  `Sentence number ${i} in this long Entry goes on and on.`;
const bodyOf = (sentences: number) =>
  Array.from({ length: sentences }, (_, i) => lineOf(i)).join("\n");
const estimateOf = (sentences: number) =>
  packPeriod([
    {
      id: "x",
      isSubject: false,
      title: "",
      body: bodyOf(sentences),
      tags: [],
      isFirstTime: false,
    },
  ]).steps[0].estimatedInputTokens;
const perSentence = (estimateOf(1001) - estimateOf(1)) / 1000;

/** An Entry whose estimate is about `tokens`. */
function sized(tokens: number, overrides: Partial<PackableEntry> = {}) {
  const sentences = Math.max(
    1,
    Math.round((tokens - estimateOf(1)) / perSentence) + 1,
  );
  return entry({ body: bodyOf(sentences), ...overrides });
}

describe("estimateTokens", () => {
  it("weights Han characters more than Latin text and adds a fixed header", () => {
    expect(estimateTokens("")).toBe(40);
    expect(estimateTokens("abc".repeat(100))).toBe(140);
    expect(estimateTokens("字".repeat(100))).toBe(Math.ceil(130) + 40);
  });
});

describe("packPeriod", () => {
  it("reads a small period in one request, note first", () => {
    const note = entry({ isSubject: true, title: "Job search" });
    const entries = [note, entry(), entry(), entry()];
    const packed = packPeriod(entries);
    expect(packed.mode).toBe("single");
    expect(packed.steps).toHaveLength(1);
    expect(packed.steps[0]).toMatchObject({ index: 0, kind: "review" });
    expect(packed.entryIds).toEqual(entries.map((item) => item.id));
    expect(packed.noteEntryId).toBe(note.id);
    expect(packed).toMatchObject({
      entriesInPeriod: 3,
      entriesRead: 3,
      trimmedEntries: 0,
      trimCodePoints: null,
    });
  });

  it("has no note for a year", () => {
    const packed = packPeriod([entry(), entry()]);
    expect(packed.noteEntryId).toBeNull();
    expect(packed.steps[0].entryIds).toHaveLength(2);
  });

  it("stays single exactly up to the single-pass limit and segments one sentence above it", () => {
    const first = sized(100_000);
    const firstCost = packPeriod([first]).steps[0].estimatedInputTokens;
    // The most sentences a second Entry can have while the two together stay within the limit.
    let low = 1;
    let high = 4_000;
    while (low < high) {
      const mid = Math.ceil((low + high) / 2);
      const total = firstCost + estimateOf(mid);
      if (total <= SINGLE_PASS_TOKENS) low = mid;
      else high = mid - 1;
    }
    const second = (sentences: number) => entry({ body: bodyOf(sentences) });
    expect(packPeriod([first, second(low)]).mode).toBe("single");
    expect(packPeriod([first, second(low + 1)]).mode).toBe("segmented");
  });

  it("splits segments only at Entry boundaries, in order, and adds a reduce step", () => {
    const entries = Array.from({ length: 8 }, () => sized(40_000));
    const packed = packPeriod(entries);
    expect(packed.mode).toBe("segmented");
    const maps = packed.steps.filter((step) => step.kind === "map");
    const reduce = packed.steps.at(-1)!;
    expect(reduce).toMatchObject({
      kind: "reduce",
      entryIds: [],
      estimatedInputTokens: REDUCE_INPUT_TOKENS,
    });
    expect(maps.flatMap((step) => step.entryIds)).toEqual(
      entries.map((item) => item.id),
    );
    for (const step of maps) {
      expect(step.estimatedInputTokens).toBeLessThanOrEqual(SEGMENT_TOKENS);
      expect(step.entryIds.length).toBeGreaterThan(0);
    }
    expect(packed.steps.map((step) => step.index)).toEqual(
      packed.steps.map((_, i) => i),
    );
    expect(packed).toMatchObject({
      trimmedEntries: 0,
      entriesRead: 8,
      trimCodePoints: null,
    });
  });

  it("keeps the Chapter note with the first part", () => {
    const note = entry({ isSubject: true, title: "Big" });
    const entries = [note, ...Array.from({ length: 6 }, () => sized(40_000))];
    const packed = packPeriod(entries);
    expect(packed.steps[0].entryIds[0]).toBe(note.id);
    expect(
      packed.steps.slice(1).every((step) => !step.entryIds.includes(note.id)),
    ).toBe(true);
    expect(packed.entryIds[0]).toBe(note.id);
  });

  it("uses at most six parts, shortening long Entries before leaving any out", () => {
    // 5 Entries of ~170k tokens do not fit in six parts of 110k, but trimmed to 6,000 code points they do.
    const entries = Array.from({ length: 5 }, () => sized(170_000));
    const packed = packPeriod(entries);
    expect(packed.trimCodePoints).toBe(TRIM_CODE_POINTS);
    expect(packed.trimmedEntries).toBe(5);
    expect(packed.entriesRead).toBe(5);
    expect(packed.entriesInPeriod).toBe(5);
    expect(
      packed.steps.filter((step) => step.kind === "map").length,
    ).toBeLessThanOrEqual(MAX_SEGMENTS);
  });

  it("shortens a single huge Entry that could never fit in a part", () => {
    const huge = sized(300_000);
    const packed = packPeriod([entry(), huge, entry()]);
    expect(packed.trimCodePoints).toBe(TRIM_CODE_POINTS);
    expect(packed.trimmedEntries).toBe(1);
    expect(packed.entriesRead).toBe(3);
  });

  it("leaves Entries out evenly when even shortened Entries are too many, keeping every First Time", () => {
    // ~3,000 Entries of ~6,000 code points each is far beyond six parts even when shortened.
    const long = (firstTime: boolean) =>
      entry({
        isFirstTime: firstTime,
        body: Array.from(
          { length: 140 },
          (_, i) => `Sentence ${i} is here and goes on a little bit longer.`,
        ).join(" "),
      });
    const entries = Array.from({ length: 1000 }, (_, i) =>
      long(i === 100 || i === 900),
    );
    const packed = packPeriod(entries);
    expect(packed.trimCodePoints).toBe(TRIM_CODE_POINTS);
    expect(packed.entriesInPeriod).toBe(1000);
    expect(packed.entriesRead).toBeGreaterThan(0);
    expect(packed.entriesRead).toBeLessThan(1000);
    expect(packed.entryIds).toContain(entries[100].id);
    expect(packed.entryIds).toContain(entries[900].id);
    expect(
      packed.steps.filter((step) => step.kind === "map").length,
    ).toBeLessThanOrEqual(MAX_SEGMENTS);
    for (const step of packed.steps)
      if (step.kind === "map")
        expect(step.estimatedInputTokens).toBeLessThanOrEqual(SEGMENT_TOKENS);
    // Chronological order is kept and the kept Entries are spread across the period.
    const order = packed.entryIds.map((id) =>
      entries.findIndex((item) => item.id === id),
    );
    expect([...order].sort((a, b) => a - b)).toEqual(order);
    const quarter = (index: number) => Math.floor(index / 250);
    expect(new Set(order.map(quarter)).size).toBe(4);
    // Taking one more Entry in the spread would not have fit, so the choice is the largest that fits.
    expect(packed.entriesRead).toBe(order.length);
  });

  it("keeps the Chapter note when Entries are left out", () => {
    const note = entry({ isSubject: true, title: "Everything" });
    const long = () =>
      entry({
        body: Array.from(
          { length: 140 },
          (_, i) => `Sentence ${i} is here and goes on a little bit longer.`,
        ).join(" "),
      });
    const packed = packPeriod([note, ...Array.from({ length: 1000 }, long)]);
    expect(packed.entryIds[0]).toBe(note.id);
    expect(packed.entriesRead).toBeLessThan(1000);
  });

  it("produces the same plan for the same input", () => {
    const entries = Array.from({ length: 8 }, () => sized(40_000));
    expect(packPeriod(entries)).toEqual(packPeriod(entries));
  });

  it("handles a period with nothing in it", () => {
    const packed = packPeriod([]);
    expect(packed).toMatchObject({
      mode: "single",
      entriesRead: 0,
      entriesInPeriod: 0,
    });
    expect(packed.steps[0].entryIds).toEqual([]);
  });
});

describe("sentPassages", () => {
  it("sends whole passages within the first code points and says when it cut", () => {
    const body = Array.from(
      { length: 200 },
      (_, i) => `This is sentence number ${i} of a long Entry.`,
    ).join(" ");
    const all = sentPassages(body, null);
    const cut = sentPassages(body, TRIM_CODE_POINTS);
    expect(all.trimmed).toBe(false);
    expect(cut.trimmed).toBe(true);
    expect(cut.passages.length).toBeLessThan(all.passages.length);
    expect(cut.passages.at(-1)!.end).toBeLessThanOrEqual(TRIM_CODE_POINTS);
    expect(sentPassages("A short one.", TRIM_CODE_POINTS).trimmed).toBe(false);
  });
});

describe("estimateJobMicros", () => {
  it("adds the largest each request may bill", () => {
    const packed = packPeriod([entry(), entry()]);
    const price = { inputMicros: 2, outputMicros: 10 };
    expect(estimateJobMicros(packed.steps, price)).toBe(
      packed.steps[0].estimatedInputTokens * 2 + 16_000 * 10,
    );
    const heavy = packPeriod(Array.from({ length: 8 }, () => sized(40_000)));
    const maps = heavy.steps.filter((step) => step.kind === "map");
    expect(estimateJobMicros(heavy.steps, price)).toBe(
      maps.reduce(
        (sum, step) => sum + step.estimatedInputTokens * 2 + 10_000 * 10,
        0,
      ) +
        REDUCE_INPUT_TOKENS * 2 +
        16_000 * 10,
    );
  });
});
