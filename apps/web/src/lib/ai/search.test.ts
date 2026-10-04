import { describe, expect, it } from "vitest";
import {
  buildSearchSources,
  evidenceParameters,
  parseAISearchInput,
  parseSearchFindings,
  parseSearchPlan,
  retrievalTerms,
  sourceQuotations,
  searchAnswerSchema,
  searchPlanSchema,
} from "./search";
const id = "11111111-1111-4111-8111-111111111111";
const plan = {
  queries: ["skiing", "滑雪"],
  itemClassifications: [],
  dateFrom: null,
  dateTo: null,
  beforeLatestHome: false,
  order: "oldest",
};
describe("AI search trust boundary", () => {
  it("constrains provider citations to real passages and rejects malformed references", () => {
    const { sources } = buildSearchSources(
      { entries: [{ id, body: "An original memory." }] },
      [],
    );
    const schema = searchAnswerSchema(sources);
    expect(
      schema.properties.findings.items.properties.citations.items.properties
        .reference.enum,
    ).toEqual(sourceQuotations(sources[0].text).map((q) => `S1:${q.id}`));
    expect(searchPlanSchema.additionalProperties).toBe(false);
    expect(searchPlanSchema.required).toContain("beforeLatestHome");
    expect(
      parseSearchFindings(
        {
          insufficientEvidence: false,
          findings: [
            { text: "A memory.", citations: [{ reference: "S1:Q1:extra" }] },
          ],
        },
        sources,
      ),
    ).toBeNull();
  });
  it("does not let an inferred type narrow All Types", () => {
    const request = parseAISearchInput({
      parameters: { q: "My earlier thoughts?" },
      timeZone: "UTC",
    })!.request;
    expect(
      evidenceParameters(
        parseSearchPlan({ ...plan, itemClassifications: ["entry"] })!,
        request,
        "2026-09-12",
      ).p_item_classifications,
    ).toEqual([]);
  });
  it("keeps readable writing separate from inspectable structured facts", () => {
    const quotations = sourceQuotations(
      'Title: Memory\nWriting:\nA short thought.\nRecorded facts:\n{"date_precision":"unknown"}',
    );
    expect(
      quotations.find((q) => q.text.includes("A short thought."))?.text,
    ).not.toContain("date_precision");
    expect(quotations.some((q) => q.text.startsWith("Recorded facts:"))).toBe(
      true,
    );
  });
  it("inserts original quotations selected by ID instead of trusting model copying", () => {
    const { sources } = buildSearchSources(
      { entries: [{ id, title: "Skiing", body: "第一次滑雪是在17岁。" }] },
      ["滑雪"],
    );
    const passage = sourceQuotations(sources[0].text).find((q) =>
      q.text.includes("第一次滑雪"),
    )!;
    const result = parseSearchFindings(
      {
        insufficientEvidence: false,
        findings: [
          {
            text: "A skiing memory.",
            citations: [
              {
                sourceID: "S1",
                quoteID: passage.id,
                quote: "fabricated translation",
              },
            ],
          },
        ],
      },
      sources,
    );
    expect(result?.findings[0].citations[0].quote).toBe(passage.text);
    expect(passage.text).toContain("第一次滑雪是在17岁。");
    expect(
      parseSearchFindings(
        {
          insufficientEvidence: false,
          findings: [
            {
              text: "A memory.",
              citations: [{ sourceID: "S1", quoteID: "Q999" }],
            },
          ],
        },
        sources,
      ),
    ).toBeNull();
  });
  it("recovers salient bilingual terms from generated first-experience phrases", () => {
    expect(
      retrievalTerms([
        "first skiing",
        "skiing attempt",
        "初次滑雪",
        "ski first time",
      ]),
    ).toEqual(["skiing", "滑雪", "ski"]);
    expect(
      retrievalTerms(["learning about electricity", "学习电力知识"]),
    ).toContain("electricity");
    expect(retrievalTerms([""])).toEqual([""]);
  });
  it("validates questions, filters and local time zones before spending", () => {
    expect(
      parseAISearchInput({
        parameters: {
          q: "第一次滑雪?",
          type: ["first_time"],
          from: "2020-01-01",
        },
        timeZone: "America/Los_Angeles",
      })?.request.itemClassifications,
    ).toEqual(["first_time"]);
    for (const parameters of [
      { q: "" },
      { q: "a".repeat(201) },
      { q: "skiing", type: 1 },
      { q: "skiing", from: "2026-02-30" },
      { q: "skiing", sql: "select *" },
    ])
      expect(parseAISearchInput({ parameters, timeZone: "UTC" })).toBeNull();
    expect(
      parseAISearchInput({ parameters: { q: "skiing" }, timeZone: "bad zone" }),
    ).toBeNull();
  });
  it("bounds planning, calendar dates, types and query expansion", () => {
    expect(parseSearchPlan(plan)?.order).toBe("oldest");
    for (const invalid of [
      { queries: Array(7).fill("a") },
      { order: "random" },
      { itemClassifications: ["unknown"] },
      { dateFrom: "2026-02-30" },
      { dateFrom: "2026-05-01", dateTo: "2026-01-01" },
      { beforeLatestHome: "yes" },
    ])
      expect(parseSearchPlan({ ...plan, ...invalid })).toBeNull();
  });
  it("keeps explicit user filters ahead of inferred model filters", () => {
    const request = parseAISearchInput({
      parameters: {
        q: "skiing",
        type: "entry",
        collection: "Travel",
        tag: "winter",
        from: "2017-01-01",
        to: "2017-12-31",
      },
      timeZone: "UTC",
    })!.request;
    expect(
      evidenceParameters(
        parseSearchPlan({
          ...plan,
          itemClassifications: ["first_time"],
          dateFrom: "2020-01-01",
        })!,
        request,
        "2026-09-12",
      ),
    ).toMatchObject({
      p_item_classifications: ["entry"],
      p_tag_names: ["winter", "Travel"],
      p_date_from: "2017-01-01",
      p_date_to: "2017-12-31",
    });
  });
  it("keeps uncertainty, verifies source IDs and excludes media", () => {
    const { sources } = buildSearchSources(
      {
        entries: [
          {
            id,
            title: "Skiing",
            body: "第一次滑雪是在17岁。",
            date_precision: "age",
            occurred_start: null,
            attachments: [{ url: "secret" }],
            owner_id: "secret",
          },
          { id: "javascript:evil", body: "bad" },
        ],
      },
      ["滑雪"],
    );
    expect(sources).toHaveLength(1);
    expect(sources[0].href).toBe(`/items/${id}`);
    expect(sources[0].text).toContain('"date_precision": "age"');
    expect(sources[0].text).not.toContain("secret");
  });
  it("rejects invented sources, altered quotes and unreferenced claims", () => {
    const { sources } = buildSearchSources(
      { entries: [{ id, title: "Skiing", body: "第一次滑雪是在17岁。" }] },
      ["滑雪"],
    );
    const finding = {
      text: "A first skiing memory at age 17.",
      citations: [{ sourceID: "S1", quote: "第一次滑雪是在17岁。" }],
    };
    expect(
      parseSearchFindings(
        { insufficientEvidence: false, findings: [finding] },
        sources,
      )?.findings,
    ).toHaveLength(1);
    for (const citations of [
      [],
      [{ sourceID: "S999", quote: "第一次滑雪是在17岁。" }],
      [{ sourceID: "S1", quote: "第一次滑雪是在18岁。" }],
    ])
      expect(
        parseSearchFindings(
          {
            insufficientEvidence: false,
            findings: [{ ...finding, citations }],
          },
          sources,
        ),
      ).toBeNull();
    expect(
      parseSearchFindings(
        { insufficientEvidence: false, findings: [] },
        sources,
      ),
    ).toBeNull();
    expect(
      parseSearchFindings({ insufficientEvidence: true, findings: [] }, sources)
        ?.insufficientEvidence,
    ).toBe(true);
  });
  it("focuses excerpts near matches and declares incomplete coverage", () => {
    const result = buildSearchSources(
      {
        entries: [
          {
            id,
            body: "a".repeat(4000) + "滑雪 happened here" + "b".repeat(2000),
          },
        ],
        query_truncated: true,
      },
      ["滑雪"],
    );
    expect(result.sources[0].text).toContain("滑雪 happened here");
    expect(result.sources[0].truncated).toBe(true);
    expect(result.notices.length).toBeGreaterThan(0);
  });
  it("bounds serialized payload even with escaped and multibyte text", () => {
    const entries = Array.from({ length: 36 }, (_, i) => ({
      id: `11111111-1111-4111-8111-${String(i).padStart(12, "0")}`,
      body: '牙\n"'.repeat(3000),
    }));
    const result = buildSearchSources({ entries }, []);
    expect(
      new TextEncoder().encode(
        JSON.stringify(result.sources.map(({ id, text }) => ({ id, text }))),
      ).length,
    ).toBeLessThan(44000);
  });
  it("declares missing precision without fabricating dates", () => {
    const { notices } = buildSearchSources(
      {
        latest_home_reference: { id, title: "Home", date_precision: "age" },
        reference_window_applied: false,
      },
      [],
    );
    expect(notices.join(" ")).toContain("uncertain date");
  });
});
