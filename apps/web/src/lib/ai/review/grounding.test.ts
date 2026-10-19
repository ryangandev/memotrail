import { describe, expect, it } from "vitest";
import {
  GroundingError,
  parseModelJson,
  resolveMap,
  resolveReview,
  type Candidate,
  type GroundingContext,
  type GroundingEntry,
} from "./grounding";
import { segmentPassages } from "./passages";

const bodies = [
  "I felt anxious about the first interview today. My hands were shaking.",
  "Practiced questions with my brother tonight. It was steadier than I feared.",
  "The second interview went better than I expected. They laughed at my joke.",
  "My first ever offer arrived this morning. I read the email four times.",
  "Waiting is the hardest part of all of this. Nothing is moving this week.",
  "I decided to accept the offer. The team seems kind and curious.",
];

function entryFor(index: number, body: string, overrides: Partial<GroundingEntry> = {}): GroundingEntry {
  const passages = segmentPassages(body);
  const day = String(index).padStart(2, "0");
  return {
    ref: `E${index}`,
    id: `00000000-0000-4000-8000-0000000000${day}`,
    revision: 1,
    isNote: false,
    body,
    windowStart: `2026-03-${day}`,
    windowEnd: `2026-03-${String(index + 1).padStart(2, "0")}`,
    passages: new Map(passages.map((passage) => [passage.id, passage])),
    sentText: passages.map((passage) => passage.text).join("\n"),
    ...overrides,
  };
}

function context(overrides: Partial<GroundingContext> = {}, extra: GroundingEntry[] = []): GroundingContext {
  const entries = new Map<string, GroundingEntry>();
  bodies.forEach((body, i) => entries.set(`E${i + 1}`, entryFor(i + 1, body)));
  for (const entry of extra) entries.set(entry.ref, entry);
  return { entries, entriesInPeriod: bodies.length, ...overrides };
}

const quote = (from: string, to: string | null = null, why = "It names the worry.") => ({ from, to, why });
const phase = (feeling: string, entries: string[], description = "It eased over a few days.") => ({
  feeling,
  description,
  entries,
});
const theme = (name: string, entries: string[], description = "It kept coming back.") => ({
  name,
  description,
  entries,
});

function review(overrides: Record<string, unknown> = {}) {
  return {
    summary: "A tense stretch that ended well.",
    feelings: {
      overview: "From worry to relief.",
      phases: [phase("Anxious, then steadier", ["E1", "E2"]), phase("Hopeful and settled", ["E4", "E6"])],
    },
    themes: [theme("Interviews", ["E1", "E3"])],
    quotes: [quote("E1.P1"), quote("E4.P1"), quote("E6.P1")],
    ...overrides,
  };
}

describe("resolveReview", () => {
  it("resolves a valid result to the exact words, offsets, and dates from the Entries", () => {
    const ctx = context();
    const content = resolveReview(review(), ctx);
    expect(content.summary).toBe("A tense stretch that ended well.");
    expect(content.quotes).toHaveLength(3);
    for (const stored of content.quotes) {
      const entry = [...ctx.entries.values()].find((item) => item.id === stored.entryId)!;
      expect(Array.from(entry.body).slice(stored.start, stored.end).join("")).toBe(stored.text);
      expect(entry.body).toContain(stored.text);
    }
    expect(content.quotes[0].text).toBe("I felt anxious about the first interview today.");
    expect(content.feelings.phases[0]).toMatchObject({
      windowStart: "2026-03-01",
      windowEnd: "2026-03-03",
      entryIds: [ctx.entries.get("E1")!.id, ctx.entries.get("E2")!.id],
    });
    expect(content.themes[0].entryIds).toEqual([ctx.entries.get("E1")!.id, ctx.entries.get("E3")!.id]);
  });

  it("extends a quote across up to three consecutive passages", () => {
    const content = resolveReview(
      review({ quotes: [quote("E1.P1", "E1.P2"), quote("E4.P1"), quote("E6.P1")] }),
      context(),
    );
    expect(content.quotes[0].text).toBe(bodies[0]);
  });

  it("removes unknown Entry IDs and duplicate citations from an item", () => {
    const content = resolveReview(
      review({
        feelings: {
          overview: "From worry to relief.",
          phases: [phase("Anxious, then steadier", ["E1", "E99", "E1", "bogus", "E2"])],
        },
      }),
      context(),
    );
    expect(content.feelings.phases[0].entryIds).toHaveLength(2);
  });

  it("drops quotes that name unknown passages, cross two Entries, run past three passages, or are too short", () => {
    const ctx = context({}, [
      entryFor(7, "Yes. No. Maybe so. Fine then. All set. Good. Sure."),
      entryFor(8, "Tiny."),
    ]);
    const content = resolveReview(
      review({
        quotes: [
          quote("E1.P1"),
          quote("E2.P99"),
          quote("E99.P1"),
          quote("E1.P1", "E2.P1"),
          quote("E7.P1", "E7.P5"),
          quote("E8.P1"),
          quote("nonsense"),
          quote("E4.P1"),
          quote("E6.P1"),
        ],
      }),
      ctx,
    );
    expect(content.quotes.map((item) => item.text)).toEqual([
      bodies[0].split(". ")[0] + ".",
      "My first ever offer arrived this morning.",
      "I decided to accept the offer.",
    ]);
  });

  it("drops a quote that overlaps an earlier one from the same Entry and duplicates", () => {
    const content = resolveReview(
      review({
        quotes: [quote("E1.P1", "E1.P2"), quote("E1.P2"), quote("E1.P1"), quote("E4.P1"), quote("E6.P1")],
      }),
      context(),
    );
    expect(content.quotes.map((item) => item.entryId).filter((id) => id.endsWith("01"))).toHaveLength(1);
  });

  it("drops a theme from a single date or a single Entry", () => {
    const ctx = context({}, [entryFor(9, "Same day again. More words here.", { windowStart: "2026-03-01", windowEnd: "2026-03-02" })]);
    const content = resolveReview(
      review({
        themes: [theme("One date", ["E1", "E9"]), theme("One entry", ["E3"]), theme("Fine", ["E1", "E3"])],
      }),
      ctx,
    );
    expect(content.themes.map((item) => item.name)).toEqual(["Fine"]);
  });

  it("drops an item whose prose quotes words no cited Entry contains, and keeps one that quotes real words", () => {
    const content = resolveReview(
      review({
        feelings: {
          overview: "From worry to relief.",
          phases: [
            phase("Anxious", ["E1", "E2"], 'You wrote "I am drowning in this" and meant it.'),
            phase("Steadier", ["E2", "E3"], 'You called it "steadier than I feared" afterwards.'),
          ],
        },
        themes: [theme("Interviews", ["E1", "E3"], "They kept coming up.")],
      }),
      context(),
    );
    expect(content.feelings.phases.map((item) => item.feeling)).toEqual(["Steadier"]);
  });

  it("checks Chinese quotation marks and corner brackets too", () => {
    const base = review();
    for (const [quoted, kept] of [
      ["“invented”", false],
      ["「invented」", false],
      ["『invented』", false],
      ["“steadier than I feared”", true],
    ] as const) {
      const call = () =>
        resolveReview(
          {
            ...base,
            feelings: {
              overview: "From worry to relief.",
              phases: [phase("Steadier", ["E2", "E3"], `They said ${quoted} later.`), phase("Hopeful", ["E4", "E6"])],
            },
          },
          context(),
        );
      const phases = call().feelings.phases.map((item) => item.feeling);
      expect(phases.includes("Steadier")).toBe(kept);
    }
  });

  it("rejects the whole result when the summary invents a quotation", () => {
    expect(() => resolveReview(review({ summary: 'You said "I quit everything".' }), context())).toThrowError(
      expect.objectContaining({ code: "invalid_review" }),
    );
  });

  it("re-dates phases from their cited Entries and sorts them in time order", () => {
    const content = resolveReview(
      review({
        feelings: {
          overview: "From worry to relief.",
          phases: [phase("Later", ["E5", "E6"]), phase("Earlier", ["E1", "E3"])],
        },
      }),
      context(),
    );
    expect(content.feelings.phases.map((item) => item.feeling)).toEqual(["Earlier", "Later"]);
    expect(content.feelings.phases[0]).toMatchObject({ windowStart: "2026-03-01", windowEnd: "2026-03-04" });
    expect(content.feelings.phases[1]).toMatchObject({ windowStart: "2026-03-05", windowEnd: "2026-03-07" });
  });

  it("gives an open-ended Entry one day", () => {
    const ctx = context({}, [entryFor(10, "Still going on today and tomorrow.", { windowStart: "2026-03-10", windowEnd: null })]);
    const content = resolveReview(
      review({ feelings: { overview: "Calm.", phases: [phase("Open", ["E10"])] } }),
      ctx,
    );
    expect(content.feelings.phases[0]).toMatchObject({ windowStart: "2026-03-10", windowEnd: "2026-03-11" });
  });

  it("limits prose length, and the counts of phases, themes, and quotes", () => {
    const long = "w".repeat(601);
    expect(() => resolveReview(review({ summary: long }), context())).toThrowError(
      expect.objectContaining({ code: "invalid_review" }),
    );
    const many = resolveReview(
      review({
        feelings: {
          overview: "From worry to relief.",
          phases: Array.from({ length: 9 }, (_, i) => phase(`Phase ${i}`, ["E1", "E2"])),
        },
        themes: Array.from({ length: 9 }, (_, i) => theme(`Theme ${i}`, ["E1", "E3"])),
      }),
      context(),
    );
    expect(many.feelings.phases).toHaveLength(6);
    expect(many.themes).toHaveLength(6);
    const droppedLong = resolveReview(
      review({ feelings: { overview: "Calm.", phases: [phase("x".repeat(61), ["E1"]), phase("Short", ["E1"])] } }),
      context(),
    );
    expect(droppedLong.feelings.phases.map((item) => item.feeling)).toEqual(["Short"]);
  });

  it("refuses a result with too little left after dropping", () => {
    expect(() => resolveReview(review({ quotes: [quote("E99.P1")] }), context())).toThrowError(
      expect.objectContaining({ code: "ungrounded_review" }),
    );
    expect(() => resolveReview(review({ themes: [theme("One", ["E1"])] }), context())).toThrowError(
      expect.objectContaining({ code: "ungrounded_review" }),
    );
    // A larger period asks for more: three quotes from ten Entries, two themes from twenty.
    expect(() =>
      resolveReview(review({ quotes: [quote("E1.P1")] }), context({ entriesInPeriod: 10 })),
    ).toThrowError(expect.objectContaining({ code: "ungrounded_review" }));
    expect(() => resolveReview(review(), context({ entriesInPeriod: 20 }))).toThrowError(
      expect.objectContaining({ code: "ungrounded_review" }),
    );
  });

  it("rejects anything that is not the expected shape", () => {
    for (const bad of [null, "text", [], {}, { summary: "x" }, review({ themes: "no" }), review({ summary: 5 })])
      expect(() => resolveReview(bad, context())).toThrowError(GroundingError);
  });

  it("never lets the model cite the Chapter's own note, but lets it quote the note", () => {
    const note = entryFor(0, "This chapter began when the layoffs were announced.", { isNote: true, windowStart: "2026-03-01", windowEnd: null });
    const ctx = context({}, [note]);
    const content = resolveReview(
      review({
        feelings: { overview: "Calm.", phases: [phase("Start", ["E0", "E1"])] },
        quotes: [quote("E0.P1"), quote("E4.P1"), quote("E6.P1")],
      }),
      ctx,
    );
    expect(content.feelings.phases[0].entryIds).toEqual([ctx.entries.get("E1")!.id]);
    expect(content.quotes.map((item) => item.entryId)).toContain(note.id);
  });

  it("only sees the passages that were sent", () => {
    const ctx = context();
    const entry = ctx.entries.get("E1")!;
    const trimmed: GroundingEntry = { ...entry, passages: new Map([[1, entry.passages.get(1)!]]) };
    ctx.entries = new Map(ctx.entries).set("E1", trimmed);
    const content = resolveReview(review({ quotes: [quote("E1.P1"), quote("E1.P2"), quote("E4.P1"), quote("E6.P1")] }), ctx);
    expect(content.quotes.map((item) => item.text)).not.toContain(entry.passages.get(2)!.text);
  });
});

describe("resolveReview as the final step of a long period", () => {
  const candidateFor = (ref: string, number: number): Candidate => {
    const entry = context().entries.get(ref)!;
    const passage = entry.passages.get(number)!;
    return { from: `${ref}.P${number}`, to: null, ref, start: passage.start, end: passage.end, text: passage.text };
  };

  it("takes quotes only from the candidates and uses their stored words", () => {
    const candidates = [candidateFor("E1", 1), candidateFor("E4", 1), candidateFor("E6", 1)];
    const ctx = context({ candidates });
    const content = resolveReview(
      review({ quotes: [quote("E1.P1"), quote("E4.P1"), quote("E6.P1"), quote("E2.P1")] }),
      ctx,
    );
    expect(content.quotes.map((item) => item.text)).toEqual(candidates.map((item) => item.text));
  });

  it("drops a candidate whose Entry no longer contains the words", () => {
    const candidates = [candidateFor("E1", 1), candidateFor("E4", 1), candidateFor("E6", 1)];
    const ctx = context({ candidates });
    ctx.entries = new Map(ctx.entries).set("E1", { ...ctx.entries.get("E1")!, body: "Rewritten entirely since then." });
    const content = resolveReview(review({ quotes: [quote("E1.P1"), quote("E4.P1"), quote("E6.P1")] }), ctx);
    expect(content.quotes).toHaveLength(2);
  });
});

describe("resolveMap", () => {
  const mapped = (overrides: Record<string, unknown> = {}) => ({
    notes: "A few tense weeks with interviews and a brother's help.",
    arc: [phase("Anxious, then steadier", ["E1", "E2"])],
    themes: [theme("Interviews", ["E1", "E3"])],
    quotes: [quote("E1.P1"), quote("E3.P1")],
    ...overrides,
  });

  it("keeps notes, arc, themes, and exact quotes by reference", () => {
    const result = resolveMap(mapped(), context());
    expect(result.notes).toContain("tense weeks");
    expect(result.arc[0]).toMatchObject({ feeling: "Anxious, then steadier", entries: ["E1", "E2"] });
    expect(result.themes[0].entries).toEqual(["E1", "E3"]);
    expect(result.quotes.map((item) => [item.from, item.ref, item.text])).toEqual([
      ["E1.P1", "E1", "I felt anxious about the first interview today."],
      ["E3.P1", "E3", "The second interview went better than I expected."],
    ]);
  });

  it("applies the map limits", () => {
    const result = resolveMap(
      mapped({
        arc: Array.from({ length: 7 }, (_, i) => phase(`Phase ${i}`, ["E1"])),
        themes: Array.from({ length: 8 }, (_, i) => theme(`Theme ${i}`, ["E1", "E3"])),
        notes: "n".repeat(1500),
      }),
      context(),
    );
    expect(result.arc).toHaveLength(4);
    expect(result.themes).toHaveLength(5);
    expect(() => resolveMap(mapped({ notes: "n".repeat(1501) }), context())).toThrowError(GroundingError);
  });

  it("needs at least one grounded phase", () => {
    expect(() => resolveMap(mapped({ arc: [phase("Nothing", ["E99"])] }), context())).toThrowError(
      expect.objectContaining({ code: "ungrounded_review" }),
    );
  });
});

describe("parseModelJson", () => {
  it("parses JSON and rejects anything else", () => {
    expect(parseModelJson('{"a":1}')).toEqual({ a: 1 });
    expect(() => parseModelJson('{"a":')).toThrowError(expect.objectContaining({ code: "invalid_review" }));
  });
});
