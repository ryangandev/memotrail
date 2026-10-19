import { beforeEach, describe, expect, it, vi } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
vi.mock("server-only", () => ({}));

const server = vi.hoisted(() => {
  class FakeAIError extends Error {
    constructor(
      public code: string,
      public status: number,
      message: string,
    ) {
      super(message);
    }
  }
  return { FakeAIError, requestAI: vi.fn() };
});
vi.mock("./server", () => ({ AIError: server.FakeAIError, requestAI: server.requestAI }));

import {
  fitSuggestionInput,
  parseSuggestionInputs,
  runChapterSuggestions,
  SUGGESTION_MAX_BYTES,
  suggestionHorizon,
  validateSuggestions,
  windowIou,
  type SuggestionContext,
  type SuggestionEntry,
} from "./chapter-suggestions";

const TODAY = "2026-10-18";
const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;

function entry(n: number, windowStart: string, extra: Partial<SuggestionEntry> = {}): SuggestionEntry {
  return {
    ref: `S${n}`,
    id: id(n),
    title: `Entry ${n}`,
    excerpt: "Packing boxes again and thinking about the new city.",
    tags: ["moving"],
    dateLabel: windowStart,
    windowStart,
    windowEnd: new Date(Date.parse(`${windowStart}T00:00:00Z`) + 86_400_000).toISOString().slice(0, 10),
    ...extra,
  };
}

// Eight Entries across June to September 2026, newest first the way the database returns them.
const days = ["2026-09-20", "2026-09-02", "2026-08-15", "2026-07-30", "2026-07-11", "2026-06-25", "2026-06-10", "2026-05-02"];
const entries = days.map((day, i) => entry(i + 1, day));

function context(extra: Partial<SuggestionContext> = {}): SuggestionContext {
  return {
    today: TODAY,
    entries: new Map(entries.map((item) => [item.ref, item])),
    chapters: [],
    suggestions: [],
    ...extra,
  };
}

const good = {
  name: "Moving to Seattle",
  start: "2026-05",
  end: null,
  rationale: "You kept returning to the move and what it meant for you.",
  entries: ["S1", "S3", "S5", "S7"],
};

describe("windowIou", () => {
  const cases: [string, [string, string | null], [string, string | null], number][] = [
    ["identical", ["2026-01-01", "2026-02-01"], ["2026-01-01", "2026-02-01"], 1],
    ["disjoint", ["2026-01-01", "2026-02-01"], ["2026-03-01", "2026-04-01"], 0],
    ["half overlap", ["2026-01-01", "2026-01-11"], ["2026-01-06", "2026-01-16"], 5 / 15],
    ["open end runs through tomorrow", ["2026-10-08", null], ["2026-10-08", "2026-10-19"], 1],
    ["empty window reads as one day", ["2026-01-01", "2026-01-01"], ["2026-01-01", "2026-01-02"], 1],
  ];
  it.each(cases)("%s", (_name, left, right, expected) => {
    expect(
      windowIou({ windowStart: left[0], windowEnd: left[1] }, { windowStart: right[0], windowEnd: right[1] }, TODAY),
    ).toBeCloseTo(expected);
  });
});

describe("validateSuggestions", () => {
  const run = (item: Record<string, unknown>, ctx = context()) =>
    validateSuggestions({ suggestions: [{ ...good, ...item }] }, ctx);

  it("keeps a well-formed suggestion and turns the S ids into Entry ids", () => {
    const [kept] = run({});
    expect(kept).toMatchObject({
      name: "Moving to Seattle",
      sourceEntryIds: [id(1), id(3), id(5), id(7)],
      startDate: "2026-05-01",
      startPrecision: "month",
      endDate: null,
      endPrecision: null,
      windowStart: "2026-05-01",
      windowEnd: null,
    });
  });

  it("reads a closed month end as the first day of the next month", () => {
    const [kept] = run({ end: "2026-09" });
    expect(kept).toMatchObject({ endDate: "2026-09-01", endPrecision: "month", windowEnd: "2026-10-01" });
  });

  it("drops a suggestion that is wrong in any way", () => {
    const wrong: Record<string, unknown>[] = [
      { name: "  " },
      { name: "x".repeat(81) },
      { name: "Two\nlines" },
      { start: "May 2026" },
      { start: "2026-13" },
      { start: "2026-02-30" },
      { start: "2026-04" }, // earlier than the earliest Entry sent
      { start: "2026-07" }, // the window no longer holds the earliest cited Entry
      { end: "2026-08" }, // the window ends before the cited Entries do
      { end: "2026-11" }, // lies after today
      { end: "2026-04" }, // ends before it starts
      { entries: ["S1", "S3", "S5"] }, // fewer than four
      { entries: ["S1", "S3", "S5", "S99"] }, // unknown ids are removed first
      { entries: ["S1", "S1", "S1", "S1"] },
      { entries: ["S1", "S2", "S3", "S3"] }, // fewer than four once repeats are removed
      { rationale: "" },
      { rationale: "y".repeat(401) },
      { rationale: 'You wrote "I will never leave this house" over and over.' },
    ];
    for (const item of wrong) expect(run(item), JSON.stringify(item)).toEqual([]);
  });

  it("accepts a quotation that appears in the cited Entries", () => {
    expect(run({ rationale: 'You wrote "Packing boxes again" and meant it.' })).toHaveLength(1);
  });

  it("allows an open end only when the newest cited Entry is recent", () => {
    expect(run({ entries: ["S4", "S5", "S6", "S7"] })).toEqual([]);
    expect(run({ entries: ["S4", "S5", "S6", "S7"], end: "2026-08" })).toHaveLength(1);
  });

  it("drops a suggestion that repeats a Chapter, a known stretch, or an earlier item", () => {
    const chapter = { title: "Moving", windowStart: "2026-05-01", windowEnd: "2026-10-01" };
    expect(run({}, context({ chapters: [chapter] }))).toEqual([]);
    expect(run({}, context({ suggestions: [{ status: "dismissed", windowStart: "2026-05-01", windowEnd: null }] }))).toEqual([]);
    expect(
      validateSuggestions({ suggestions: [good, { ...good, name: "Another name" }] }, context()),
    ).toHaveLength(1);
    expect(run({}, context({ chapters: [{ title: "Elsewhere", windowStart: "2024-01-01", windowEnd: "2024-03-01" }] }))).toHaveLength(1);
  });

  it("drops a name that matches an existing Chapter ignoring case", () => {
    const chapter = { title: "moving to seattle", windowStart: "2020-01-01", windowEnd: "2020-02-01" };
    expect(run({}, context({ chapters: [chapter] }))).toEqual([]);
  });

  it("keeps at most the room that pending suggestions leave", () => {
    const pending = (count: number) =>
      Array.from({ length: count }, (_, n) => ({ status: "pending", windowStart: `2020-0${n + 1}-01`, windowEnd: `2020-0${n + 1}-10` }));
    expect(validateSuggestions({ suggestions: [good] }, context({ suggestions: pending(2) }))).toHaveLength(1);
    expect(validateSuggestions({ suggestions: [good] }, context({ suggestions: pending(3) }))).toEqual([]);
  });

  it("returns nothing for an answer of the wrong shape", () => {
    expect(validateSuggestions(null, context())).toEqual([]);
    expect(validateSuggestions({ suggestions: "none" }, context())).toEqual([]);
    expect(validateSuggestions({ suggestions: [null, 3] }, context())).toEqual([]);
  });
});

describe("input", () => {
  const row = (n: number, day: string, excerpt = "Some words.") => ({
    id: id(n),
    title: `T${n}`,
    excerpt,
    tags: ["a"],
    occurredStart: `${day}T12:00:00Z`,
    occurredEnd: null,
    datePrecision: "day",
    occurredLabel: null,
    occurredTimezone: "UTC",
    windowStart: day,
    windowEnd: null,
  });

  it("numbers Entries newest first and keeps the Chapters and earlier windows", () => {
    const inputs = parseSuggestionInputs({
      entries: [row(1, "2026-09-20"), row(2, "2026-09-02")],
      chapters: [{ title: "Studying", occurredStart: "2023-09-01T00:00:00Z", occurredEnd: "2025-05-01T00:00:00Z", datePrecision: "month", occurredTimezone: "UTC", windowStart: "2023-09-01", windowEnd: "2025-06-01" }],
      suggestions: [{ status: "pending", windowStart: "2026-03-01", windowEnd: "2026-07-01" }],
    })!;
    expect(inputs.entries.map((item) => item.ref)).toEqual(["S1", "S2"]);
    expect(inputs.entries[0].windowEnd).toBe("2026-09-21");
    expect(inputs.chapters[0]).toMatchObject({ title: "Studying", span: "Sep 2023 - May 2025" });
    expect(inputs.suggestions).toEqual([{ status: "pending", windowStart: "2026-03-01", windowEnd: "2026-07-01" }]);
  });

  it("rejects malformed data", () => {
    expect(parseSuggestionInputs(null)).toBeNull();
    expect(parseSuggestionInputs({ entries: [] })).toBeNull();
  });

  it("sends only spans of earlier suggestions, never what they were named", () => {
    const inputs = parseSuggestionInputs({
      entries: [row(1, "2026-09-20")],
      chapters: [],
      suggestions: [{ status: "dismissed", windowStart: "2026-03-01", windowEnd: "2026-07-01" }],
    })!;
    const { input } = fitSuggestionInput(inputs, TODAY);
    expect(JSON.parse(input).earlierSuggestions).toEqual([{ span: "March 2026 - June 2026" }]);
  });

  it("shortens excerpts and then drops the oldest Entries to stay within the limit", () => {
    const long = "word ".repeat(100);
    const many = Array.from({ length: 600 }, (_, i) => row(i + 1, "2026-09-20", long));
    const inputs = parseSuggestionInputs({ entries: many, chapters: [], suggestions: [] })!;
    const fitted = fitSuggestionInput(inputs, TODAY);
    expect(Buffer.byteLength(fitted.input, "utf8")).toBeLessThanOrEqual(SUGGESTION_MAX_BYTES);
    expect(fitted.entries.length).toBeGreaterThan(100);
    expect(fitted.entries.length).toBeLessThan(600);
    expect(fitted.entries[0].ref).toBe("S1");
    const heavy = Array.from({ length: 600 }, (_, i) => row(i + 1, "2026-09-20", "字".repeat(500)));
    const cjk = fitSuggestionInput(parseSuggestionInputs({ entries: heavy, chapters: [], suggestions: [] })!, TODAY);
    expect(Buffer.byteLength(cjk.input, "utf8")).toBeLessThanOrEqual(SUGGESTION_MAX_BYTES);
    expect(cjk.entries.every((item) => Array.from(item.excerpt).length <= 200)).toBe(true);
  });

  it("looks back eighteen months from the start of this month", () => {
    expect(suggestionHorizon(TODAY)).toBe("2025-04-01");
  });
});

describe("runChapterSuggestions", () => {
  const LEASE = "2026-10-18T12:05:00+00:00";
  const FakeAIError = server.FakeAIError;

  function inputsFor(count: number) {
    const base = Date.parse("2026-09-28T00:00:00Z");
    return {
      entries: Array.from({ length: count }, (_, i) => {
        const day = new Date(base - i * 7 * 86_400_000).toISOString().slice(0, 10);
        return {
          id: id(i + 1),
          title: `Entry ${i + 1}`,
          excerpt: "Packing boxes again and thinking about the new city.",
          tags: ["moving"],
          occurredStart: `${day}T12:00:00Z`,
          occurredEnd: null,
          datePrecision: "day",
          occurredLabel: null,
          occurredTimezone: "UTC",
          windowStart: day,
          windowEnd: new Date(Date.parse(`${day}T00:00:00Z`) + 86_400_000).toISOString().slice(0, 10),
        };
      }),
      chapters: [],
      suggestions: [],
    };
  }

  function makeClient(options: { due?: boolean; entries?: number } = {}) {
    const calls: { name: string; args: Record<string, unknown> }[] = [];
    const client = {
      rpc: vi.fn(async (name: string, args: Record<string, unknown> = {}) => {
        calls.push({ name, args });
        switch (name) {
          case "claim_chapter_suggestion_run":
            return { data: options.due === false ? { due: false } : { due: true, leaseUntil: LEASE }, error: null };
          case "chapter_suggestion_inputs":
            return { data: inputsFor(options.entries ?? 14), error: null };
          case "store_chapter_suggestions":
            return { data: (args.p_suggestions as unknown[]).length, error: null };
          default:
            return { data: true, error: null };
        }
      }),
    } as unknown as SupabaseClient;
    return { client, calls, names: () => calls.map((call) => call.name) };
  }

  beforeEach(() => server.requestAI.mockReset());

  it("does nothing when no run is due", async () => {
    const { client, names } = makeClient({ due: false });
    expect(await runChapterSuggestions(client, "owner", TODAY)).toEqual({ status: "skipped" });
    expect(names()).toEqual(["claim_chapter_suggestion_run"]);
    expect(server.requestAI).not.toHaveBeenCalled();
  });

  it("records an empty run without calling the model when there are too few Entries", async () => {
    const { client, calls } = makeClient({ entries: 11 });
    expect(await runChapterSuggestions(client, "owner", TODAY)).toEqual({ status: "stored", stored: 0 });
    expect(server.requestAI).not.toHaveBeenCalled();
    expect(calls.at(-1)).toMatchObject({ name: "store_chapter_suggestions", args: { p_suggestions: [], p_lease_until: LEASE } });
  });

  it("stores the suggestions that validate and asks with the suggestion limits", async () => {
    server.requestAI.mockResolvedValue({
      text: JSON.stringify({
        suggestions: [
          { name: "Moving to Seattle", start: "2026-07", end: null, rationale: "You kept returning to the move.", entries: ["S1", "S2", "S3", "S4", "S5"] },
          { name: "Nonsense", start: "2026-07", end: null, rationale: "Bad.", entries: ["S1"] },
        ],
      }),
      model: "claude-sonnet-5-5",
    });
    const { client, calls } = makeClient();
    expect(await runChapterSuggestions(client, "owner", TODAY)).toEqual({ status: "stored", stored: 1 });
    const request = server.requestAI.mock.calls[0][0];
    expect(request).toMatchObject({ feature: "chapter_suggestion", maxTokens: 6000, timeoutMs: 120_000 });
    expect(JSON.parse(request.input).entries[0]).toMatchObject({ id: "S1", excerptOnly: true });
    const store = calls.at(-1)!;
    expect(store.args.p_model).toBe("claude-sonnet-5-5");
    expect(store.args.p_suggestions).toHaveLength(1);
    expect(store.args.p_disclosure_version).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  });

  it("gives the lease back when nothing was charged", async () => {
    server.requestAI.mockRejectedValueOnce(new FakeAIError("budget_exceeded", 429, "budget"));
    const { client, names } = makeClient();
    expect(await runChapterSuggestions(client, "owner", TODAY)).toEqual({ status: "released", code: "budget_exceeded" });
    expect(names().at(-1)).toBe("release_chapter_suggestion_run");
  });

  it.each(["provider_interrupted", "review_declined", "incomplete_generation"])(
    "records an empty run after the uncertain outcome %s",
    async (code) => {
      server.requestAI.mockRejectedValueOnce(new FakeAIError(code, 502, "x"));
      const { client, names } = makeClient();
      expect(await runChapterSuggestions(client, "owner", TODAY)).toEqual({ status: "stored", stored: 0 });
      expect(names().at(-1)).toBe("store_chapter_suggestions");
      expect(names()).not.toContain("release_chapter_suggestion_run");
    },
  );

  it("records an empty run when the model answers with something that is not JSON", async () => {
    server.requestAI.mockResolvedValue({ text: "not json", model: "claude-sonnet-5-5" });
    const { client, calls } = makeClient();
    expect(await runChapterSuggestions(client, "owner", TODAY)).toEqual({ status: "stored", stored: 0 });
    expect(calls.at(-1)!.args.p_suggestions).toEqual([]);
  });
});
