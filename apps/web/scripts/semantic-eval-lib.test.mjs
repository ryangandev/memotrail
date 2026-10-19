import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createFakeEmbeddingServer } from "./fake-embedding-server.mjs";
import {
  bestFloor,
  candidateProfiles,
  cosine,
  evaluateModel,
  fixture,
  formatQuery,
  formatReport,
  httpEmbedder,
  nonEnglishRecall,
  percentile,
  recommend,
} from "./semantic-eval-lib.mjs";

describe("the evaluation fixture", () => {
  it("has about forty Entries and thirty queries across every language group", () => {
    expect(fixture.entries.length).toBeGreaterThanOrEqual(38);
    expect(fixture.queries.length).toBeGreaterThanOrEqual(30);
    expect(new Set(fixture.queries.map((query) => query.category))).toEqual(
      new Set(["en", "zh", "cross", "mixed", "none"]),
    );
  });

  it("only expects Entries that exist, with unique IDs", () => {
    const ids = fixture.entries.map((entry) => entry.id);
    expect(new Set(ids).size).toBe(ids.length);
    for (const query of fixture.queries) {
      for (const expected of query.expected) expect(ids).toContain(expected);
    }
  });
});

describe("evaluation arithmetic", () => {
  it("measures cosine and percentiles", () => {
    expect(cosine([1, 0], [1, 0])).toBe(1);
    expect(cosine([1, 0], [0, 1])).toBe(0);
    expect(percentile([1, 2, 3, 4, 5], 0.5)).toBe(3);
    expect(percentile([], 0.5)).toBeNull();
  });

  it("finds the floor that separates relevant from irrelevant similarities", () => {
    const { floor } = bestFloor([0.7, 0.8, 0.9], [0.1, 0.2, 0.3]);
    expect(floor).toBeGreaterThanOrEqual(0.31);
    expect(floor).toBeLessThanOrEqual(0.7);
  });

  it("formats a query with the profile's template", () => {
    expect(formatQuery(candidateProfiles.current, "bikes")).toContain(
      "\nQuery:bikes",
    );
    expect(formatQuery(candidateProfiles.harrier, "bikes")).toContain(
      "\nQuery: bikes",
    );
  });
});

describe("the challenger rule", () => {
  const report = (recall) => ({
    perQuery: [
      { category: "zh", hits: recall, id: "a", reciprocalRank: 1, wanted: 1 },
      { category: "en", hits: 0, id: "b", reciprocalRank: 0, wanted: 1 },
    ],
  });

  it("ignores English queries when scoring", () => {
    expect(nonEnglishRecall(report(1))).toBe(1);
  });

  it("switches only when the challenger is within two points", () => {
    const baseline = { name: "current", report: report(1) };
    const close = {
      name: "harrier",
      report: {
        perQuery: Array.from({ length: 100 }, (_, index) => ({
          category: "zh",
          hits: index < 99 ? 1 : 0,
          id: String(index),
          reciprocalRank: 1,
          wanted: 1,
        })),
      },
    };
    const far = { name: "harrier", report: report(0) };

    expect(recommend(baseline, close).choice).toBe("harrier");
    expect(recommend(baseline, far).choice).toBe("current");
  });
});

describe("evaluating a model server", () => {
  const fake = createFakeEmbeddingServer({ apiKey: "eval-key" });
  let report;

  beforeAll(async () => {
    const url = await fake.start();
    report = await evaluateModel({
      embed: httpEmbedder({ apiKey: "eval-key", model: "fake", url }),
      profile: candidateProfiles.current,
    });
  });
  afterAll(() => fake.stop());

  it("finds the expected Entries in English, Chinese, mixed, and cross-language queries", () => {
    expect(report.overall.recallAt5).toBeGreaterThanOrEqual(0.95);
    for (const category of ["en", "zh", "cross", "mixed"]) {
      expect(report.byCategory[category].recallAt5).toBeGreaterThanOrEqual(0.9);
    }
  });

  it("keeps no-answer queries below the suggested floor", () => {
    expect(report.floor.noAnswerQueries).toBe(4);
    expect(report.floor.noAnswerQueriesAboveFloor).toBe(0);
    expect(report.relevant.median).toBeGreaterThan(report.irrelevant.p95);
  });

  it("prints a readable report", () => {
    const text = formatReport([{ name: "current", report }], null);
    expect(text).toContain("== current ==");
    expect(text).toContain("suggested minSimilarity");
  });
});
