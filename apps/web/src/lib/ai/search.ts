import {
  parseSearchRequest,
  type RawSearchParams,
  type SearchRequest,
} from "../data/search-input";

export type AISearchInput = { parameters: RawSearchParams; timeZone: string };
export type SearchPlan = {
  queries: string[];
  itemClassifications: string[];
  dateFrom: string | null;
  dateTo: string | null;
  beforeLatestHome: boolean;
  order: "relevance" | "oldest" | "newest";
};
export type SearchSource = {
  id: string;
  recordID: string;
  title: string;
  text: string;
  href: string;
  truncated: boolean;
};
export type SearchFinding = {
  text: string;
  citations: { sourceID: string; quote: string }[];
};
export type AISearchResponse = {
  question: string;
  findings: SearchFinding[];
  sources: SearchSource[];
  notices: string[];
  insufficientEvidence: boolean;
  queries: string[];
};
// Intent words need not occur in the original Entry. In particular, the query
// "初次滑雪" must still find writing containing "第一次滑雪".
export function retrievalTerms(queries: string[]) {
  const intent = new Set([
    "first",
    "time",
    "when",
    "did",
    "i",
    "my",
    "try",
    "tried",
    "attempt",
    "learned",
    "learning",
    "about",
    "things",
    "show",
    "me",
    "the",
    "a",
    "an",
    "of",
    "初次",
    "首次",
    "第一次",
    "第",
    "一次",
    "尝试",
    "学习",
    "关于",
    "我",
    "的",
  ]);
  const segmenter = new Intl.Segmenter("zh", { granularity: "word" });
  const perQuery = queries.map((query) => {
    if (!query.trim()) return [""];
    const segments = [...segmenter.segment(query)]
      .filter((s) => s.isWordLike)
      .map((s) => s.segment.toLowerCase());
    const core = segments.filter((s) => !intent.has(s));
    return core.length ? core : [query.trim().toLowerCase()];
  });
  // Round-robin preserves bilingual coverage even when the first phrase is long.
  const terms: string[] = [];
  for (let i = 0; i < Math.max(0, ...perQuery.map((q) => q.length)); i++) {
    for (const words of perQuery)
      if (words[i] !== undefined && !terms.includes(words[i]))
        terms.push(words[i]);
  }
  return terms.slice(0, 6);
}

const types = [
  "entry",
  "entity",
  "goal",
  "first_time",
  "period",
  "home",
  "vehicle",
];
const acceptedManualTypes = new Set(types);
export const searchPlanSchema = {
  type: "object",
  additionalProperties: false,
  required: [
    "queries",
    "itemClassifications",
    "dateFrom",
    "dateTo",
    "beforeLatestHome",
    "order",
  ],
  properties: {
    queries: {
      type: "array",
      minItems: 1,
      description:
        "One to six short bilingual search terms, each under 200 characters. Use an empty string for broad retrieval.",
      items: { type: "string" },
    },
    itemClassifications: {
      type: "array",
      items: { type: "string", enum: types },
    },
    dateFrom: { anyOf: [{ type: "string", format: "date" }, { type: "null" }] },
    dateTo: { anyOf: [{ type: "string", format: "date" }, { type: "null" }] },
    beforeLatestHome: { type: "boolean" },
    order: { type: "string", enum: ["relevance", "oldest", "newest"] },
  },
};
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
function object(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}
function date(value: unknown): value is string | null {
  if (value === null) return true;
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value))
    return false;
  const d = new Date(`${value}T00:00:00Z`);
  return Number.isFinite(d.getTime()) && d.toISOString().slice(0, 10) === value;
}
export function parseAISearchInput(
  raw: unknown,
): { request: SearchRequest; timeZone: string } | null {
  const v = object(raw),
    p = object(v.parameters);
  if (
    typeof v.timeZone !== "string" ||
    v.timeZone.length > 100 ||
    !v.parameters
  )
    return null;
  const allowed = ["q", "type", "collection", "tag", "from", "to"];
  if (
    Object.entries(p).some(
      ([k, value]) =>
        !allowed.includes(k) ||
        !(
          typeof value === "string" ||
          (Array.isArray(value) &&
            value.length <= 50 &&
            value.every((s) => typeof s === "string"))
        ),
    )
  )
    return null;
  try {
    new Intl.DateTimeFormat("en", { timeZone: v.timeZone });
  } catch {
    return null;
  }
  const parsed = parseSearchRequest(p as RawSearchParams);
  if (
    parsed.error ||
    !parsed.request.query ||
    parsed.request.itemClassifications.some(
      (classification) => !acceptedManualTypes.has(classification),
    )
  )
    return null;
  return { request: parsed.request, timeZone: v.timeZone };
}
export function parseSearchPlan(raw: unknown): SearchPlan | null {
  const v = object(raw);
  if (
    !Array.isArray(v.queries) ||
    v.queries.length < 1 ||
    v.queries.length > 6 ||
    v.queries.some((q) => typeof q !== "string" || q.length > 200) ||
    !Array.isArray(v.itemClassifications) ||
    v.itemClassifications.some((t) => !types.includes(t)) ||
    v.itemClassifications.length > 6 ||
    !date(v.dateFrom) ||
    !date(v.dateTo) ||
    (v.dateFrom && v.dateTo && v.dateFrom > v.dateTo) ||
    typeof v.beforeLatestHome !== "boolean" ||
    !["relevance", "oldest", "newest"].includes(String(v.order))
  )
    return null;
  return {
    queries: [...new Set((v.queries as string[]).map((q) => q.trim()))],
    itemClassifications: v.itemClassifications as string[],
    dateFrom: v.dateFrom,
    dateTo: v.dateTo,
    beforeLatestHome: v.beforeLatestHome,
    order: v.order as SearchPlan["order"],
  };
}
export function evidenceParameters(
  plan: SearchPlan,
  request: SearchRequest,
  asOf: string,
) {
  // Explicit user filters take precedence over model-inferred filters.
  return {
    p_queries: plan.queries,
    // All Types really means all types. Thoughts can live inside a First Time
    // or Home, so model-inferred labels must not silently narrow the archive.
    p_item_classifications: request.itemClassifications,
    p_tag_names: request.tagNames,
    p_date_from: request.dateFrom ?? plan.dateFrom,
    p_date_to: request.dateTo ?? plan.dateTo,
    p_before_latest_home: plan.beforeLatestHome,
    p_order: plan.order,
    p_as_of: asOf,
  };
}
export function sourceQuotations(text: string) {
  const parts: string[] = [];
  // Separate the original writing from machine-readable facts so a citation
  // does not turn a short memory into a wall of metadata on either client.
  for (const section of text.split(/(?=Writing:\n|Recorded facts:\n)/)) {
    for (let start = 0; start < section.length;) {
      let end = Math.min(start + 600, section.length);
      const boundary = section.lastIndexOf("\n", end - 1);
      if (end < section.length && boundary > start + 100) end = boundary + 1;
      const part = section.slice(start, end);
      if (part.trim().length >= 4) parts.push(part);
      start = end;
    }
  }
  return parts.map((text, index) => ({ id: `Q${index + 1}`, text }));
}

export function searchAnswerSchema(sources: SearchSource[]) {
  return {
    type: "object",
    additionalProperties: false,
    required: ["insufficientEvidence", "findings"],
    properties: {
      insufficientEvidence: { type: "boolean" },
      findings: {
        type: "array",
        items: {
          type: "object",
          additionalProperties: false,
          required: ["text", "citations"],
          properties: {
            text: {
              type: "string",
              description:
                "At most 1000 characters, supported by the selected passages.",
            },
            citations: {
              type: "array",
              minItems: 1,
              description: "Select 1 to 3 references.",
              items: {
                type: "object",
                additionalProperties: false,
                required: ["reference"],
                properties: {
                  reference: {
                    type: "string",
                    enum: sources.flatMap((source) =>
                      sourceQuotations(source.text).map(
                        (q) => `${source.id}:${q.id}`,
                      ),
                    ),
                  },
                },
              },
            },
          },
        },
      },
    },
  };
}

function excerpt(text: string, queries: string[], limit: number) {
  if (text.length <= limit) return text;
  const positions = queries
    .filter((q) => q.trim())
    .map((q) => text.toLowerCase().indexOf(q.toLowerCase()))
    .filter((i) => i >= 0);
  const start = Math.max(
    0,
    (positions.length ? Math.min(...positions) : 0) - Math.floor(limit / 4),
  );
  return text.slice(start, start + limit);
}
// All source IDs and URLs come from authenticated database rows, never from a model.
export function buildSearchSources(raw: unknown, queries: string[]) {
  const evidence = object(raw),
    sources: SearchSource[] = [],
    notices: string[] = [];
  const rows = (v: unknown) => (Array.isArray(v) ? v.map(object) : []);
  let bytes = 0;
  const add = (row: Record<string, unknown>) => {
    if (
      typeof row.id !== "string" ||
      !uuid.test(row.id) ||
      sources.some((s) => s.recordID === row.id)
    )
      return;
    const title = String(row.title || "Untitled Entry").slice(0, 200);
    const selected = Object.fromEntries(
      [
        "item_kind",
        "item_subtype",
        "date_precision",
        "occurred_start",
        "occurred_end",
        "occurred_label",
        "occurred_timezone",
        "tags",
        "facts",
      ].map((k) => [k, row[k]]),
    );
    const facts = JSON.stringify(
      selected,
      (key, value) =>
        ["id", "owner_id", "linked_entry_ids", "revision"].includes(key)
          ? undefined
          : value,
      2,
    );
    const body = typeof row.body === "string" ? row.body : "";
    const text = `Title: ${title}\n${body ? `Writing:\n${excerpt(body, queries, 1800)}\n` : ""}Recorded facts:\n${excerpt(facts, queries, 1800)}`;
    const size = Math.max(
      new TextEncoder().encode(JSON.stringify({ id: "S50", text })).length + 1,
      new TextEncoder().encode(
        JSON.stringify({ id: "S50", quotations: sourceQuotations(text) }),
      ).length + 1,
    );
    if (bytes + size > 42_000 || sources.length >= 50) {
      notices.push(
        "Some sources were omitted to keep the AI request bounded. Narrow the question or filters.",
      );
      return;
    }
    bytes += size;
    sources.push({
      id: `S${sources.length + 1}`,
      recordID: row.id,
      title,
      text,
      href: `/items/${row.id}`,
      truncated: body.length > 1800 || facts.length > 1800,
    });
  };
  rows(evidence.entries).forEach((r) => add(r));
  if (evidence.latest_home_reference)
    add(object(evidence.latest_home_reference));
  if (evidence.query_truncated || Number(evidence.candidate_count) > 36)
    notices.push(
      "This answer uses a bounded selection of matches, not the complete archive. Narrow the question to improve coverage.",
    );
  if (evidence.latest_home_reference && !evidence.reference_window_applied)
    notices.push(
      "The latest Home has an uncertain date. A precise before-move boundary could not be applied.",
    );
  if (sources.some((s) => s.truncated))
    notices.push(
      "Long sources use excerpts. Open the original record for full context.",
    );
  return { sources, notices: [...new Set(notices)] };
}
export function parseSearchFindings(
  raw: unknown,
  sources: SearchSource[],
): { findings: SearchFinding[]; insufficientEvidence: boolean } | null {
  const v = object(raw);
  if (
    typeof v.insufficientEvidence !== "boolean" ||
    !Array.isArray(v.findings) ||
    v.findings.length > 6
  )
    return null;
  const findings: SearchFinding[] = [];
  for (const item of v.findings) {
    const f = object(item);
    if (
      typeof f.text !== "string" ||
      !f.text.trim() ||
      f.text.length > 1000 ||
      !Array.isArray(f.citations) ||
      !f.citations.length ||
      f.citations.length > 3
    )
      return null;
    const citations: SearchFinding["citations"] = [];
    for (const item of f.citations) {
      const c = object(item);
      const pair =
        typeof c.reference === "string"
          ? c.reference.toUpperCase().split(":")
          : [];
      if (typeof c.reference === "string" && pair.length !== 2) return null;
      const source = sources.find((s) => s.id === (pair[0] ?? c.sourceID));
      const quoteID = pair[1] ?? c.quoteID;
      const quote =
        typeof quoteID === "string" && source
          ? sourceQuotations(source.text).find((q) => q.id === quoteID)?.text
          : c.quote;
      if (
        !source ||
        typeof quote !== "string" ||
        quote.trim().length < 4 ||
        quote.length > 600 ||
        !source.text.includes(quote)
      )
        return null;
      citations.push({ sourceID: source.id, quote });
    }
    findings.push({ text: f.text.trim(), citations });
  }
  if (!v.insufficientEvidence && !findings.length) return null;
  return { findings, insufficientEvidence: v.insufficientEvidence };
}
