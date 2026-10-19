import { beforeEach, expect, it, vi } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
vi.mock("server-only", () => ({}));
vi.mock("./server", () => ({
  AIError: class extends Error {
    constructor(
      public code: string,
      public status: number,
      message: string,
    ) {
      super(message);
    }
  },
  generateAI: vi.fn(),
}));
import { generateAI } from "./server";
import { searchWithAI } from "./search-server";
const generate = vi.mocked(generateAI);
const rpc = vi.fn();
const client = { rpc } as unknown as SupabaseClient;
const input = { parameters: { q: "When did I first ski?" }, timeZone: "UTC" };
const plan = {
  queries: ["skiing", "滑雪"],
  itemClassifications: [],
  dateFrom: null,
  dateTo: null,
  order: "oldest",
};
const output = (v: unknown) => ({
  text: JSON.stringify(v),
  model: "test",
  usageID: "test",
});
const evidence = {
  entries: [
    {
      id: "11111111-1111-4111-8111-111111111111",
      title: "Skiing",
      body: "第一次滑雪是在17岁。",
      date_precision: "age",
    },
  ],
};
beforeEach(() => {
  vi.clearAllMocks();
  rpc.mockResolvedValue({ data: evidence, error: null });
});
it("plans bilingually, retrieves owner-client evidence, and validates original quotes", async () => {
  generate.mockResolvedValueOnce(output(plan)).mockResolvedValueOnce(
    output({
      insufficientEvidence: false,
      findings: [
        {
          text: "At age 17.",
          citations: [{ sourceID: "S1", quote: "第一次滑雪是在17岁。" }],
        },
      ],
    }),
  );
  const answer = await searchWithAI(client, "owner", input);
  expect(rpc).toHaveBeenCalledWith(
    "archive_wiki_search_evidence",
    expect.objectContaining({
      p_queries: ["skiing", "滑雪"],
      p_order: "oldest",
    }),
  );
  expect(
    generate.mock.calls.every(
      (call) => call[0] === "owner" && call[1] === "search",
    ),
  ).toBe(true);
  expect(answer.findings[0].citations[0].quote).toBe("第一次滑雪是在17岁。");
  expect(answer.sources[0].href).toContain("/items/");
});
it("spends nothing for invalid input", async () => {
  await expect(
    searchWithAI(client, "owner", { parameters: { q: "" }, timeZone: "UTC" }),
  ).rejects.toMatchObject({ code: "invalid_request" });
  expect(generate).not.toHaveBeenCalled();
  expect(rpc).not.toHaveBeenCalled();
});
it("does not call the answer model if retrieval has no evidence", async () => {
  generate.mockResolvedValueOnce(output(plan));
  rpc.mockResolvedValue({ data: { entries: [] }, error: null });
  expect(
    (await searchWithAI(client, "owner", input)).insufficientEvidence,
  ).toBe(true);
  expect(generate).toHaveBeenCalledTimes(1);
});
it("uses a declared bounded fallback when cross-language words have no overlap", async () => {
  generate
    .mockResolvedValueOnce(output(plan))
    .mockResolvedValueOnce(
      output({ insufficientEvidence: true, findings: [] }),
    );
  rpc
    .mockResolvedValueOnce({ data: { entries: [] }, error: null })
    .mockResolvedValueOnce({ data: evidence, error: null });
  const answer = await searchWithAI(client, "owner", input);
  expect(rpc).toHaveBeenLastCalledWith(
    "archive_wiki_search_evidence",
    expect.objectContaining({ p_queries: [""] }),
  );
  expect(answer.notices.join(" ")).toContain("bounded record window");
  expect(answer.insufficientEvidence).toBe(true);
});
it("never retries or displays forged citations", async () => {
  generate.mockResolvedValueOnce(output(plan)).mockResolvedValueOnce(
    output({
      insufficientEvidence: false,
      findings: [
        {
          text: "Invented date",
          citations: [{ sourceID: "other-owner", quote: "not in source" }],
        },
      ],
    }),
  );
  await expect(searchWithAI(client, "owner", input)).rejects.toMatchObject({
    code: "ungrounded_answer",
  });
  expect(generate).toHaveBeenCalledTimes(2);
});
it("broadens an empty keyword match without discarding manual filters", async () => {
  generate
    .mockResolvedValueOnce(
      output({ ...plan, itemClassifications: ["entry"] }),
    )
    .mockResolvedValueOnce(
      output({ insufficientEvidence: true, findings: [] }),
    );
  rpc
    .mockResolvedValueOnce({ data: { entries: [] }, error: null })
    .mockResolvedValueOnce({ data: evidence, error: null });
  const answer = await searchWithAI(client, "owner", {
    ...input,
    parameters: { q: "What was I thinking last winter?", tag: "life" },
  });
  expect(rpc).toHaveBeenLastCalledWith(
    "archive_wiki_search_evidence",
    expect.objectContaining({
      p_queries: [""],
      p_item_classifications: [],
      p_tag_names: ["life"],
    }),
  );
  expect(rpc.mock.calls[0]?.[1]).not.toHaveProperty("p_before_latest_home");
  expect(rpc.mock.calls[0]?.[1]).not.toHaveProperty("p_as_of");
  expect(answer.sources.map((source) => source.recordID)).toContain(
    evidence.entries[0].id,
  );
  expect(answer.notices.join(" ")).toContain("bounded record window");
});
it("rejects an invalid planner response without querying records", async () => {
  generate.mockResolvedValueOnce(output({ queries: ["DROP TABLE"] }));
  await expect(searchWithAI(client, "owner", input)).rejects.toMatchObject({
    code: "invalid_plan",
  });
  expect(rpc).not.toHaveBeenCalled();
});
it("retains manual filters over inferred Chapter and First Time labels", async () => {
  generate
    .mockResolvedValueOnce(
      output({ ...plan, itemClassifications: ["chapter", "first_time"] }),
    )
    .mockResolvedValueOnce(
      output({ insufficientEvidence: true, findings: [] }),
    );
  const answer = await searchWithAI(client, "owner", {
    ...input,
    parameters: {
      q: "Before I left Portland?",
      type: "entry",
      tag: "life",
      from: "2020-01-01",
      to: "2026-01-01",
    },
  });
  expect(rpc).toHaveBeenCalledWith(
    "archive_wiki_search_evidence",
    expect.objectContaining({
      p_item_classifications: ["entry"],
      p_tag_names: ["life"],
      p_date_from: "2020-01-01",
      p_date_to: "2026-01-01",
    }),
  );
  expect(answer.notices.join(" ")).not.toContain("Home");
});
it("tells the planner the three classifications and no before-move boundary", async () => {
  generate
    .mockResolvedValueOnce(output(plan))
    .mockResolvedValueOnce(output({ insufficientEvidence: true, findings: [] }));
  await searchWithAI(client, "owner", input);
  const instructions = String(generate.mock.calls[0]?.[2]);
  expect(instructions).toContain(
    "Valid classifications are entry, chapter, and first_time",
  );
  expect(instructions).not.toMatch(/beforeLatestHome|vehicle|milestone|move/i);
});
