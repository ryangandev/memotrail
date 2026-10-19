import Anthropic from "@anthropic-ai/sdk";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import {
  BAD_QUOTE_SENTINEL,
  OUTAGE_SENTINEL,
  REFUSAL_SENTINEL,
  createFakeAIProvider,
  fakeAnswer,
  parseDateLabel,
} from "./fake-ai-provider.mjs";

vi.mock("server-only", () => ({}));
import { resolveMap, resolveReview } from "../src/lib/ai/review/grounding";
import { segmentPassages } from "../src/lib/ai/review/passages";
import { validateSuggestions } from "../src/lib/ai/chapter-suggestions";
import {
  buildChapterSuggestionInput,
  buildMapInput,
  buildReviewInput,
} from "../src/lib/ai/review/prompts";

const bodies = [
  "Sent the first application today. It felt strange to hit the button.",
  "Waited all week for an answer. The waiting is the hardest part of this.",
  "A phone screen went better than I feared. I talked for forty minutes.",
  "Took a long walk to clear my head. Everything feels a little lighter.",
  "Second round was tough but I kept my calm. I want this job more now.",
  "An offer came in at last. I read the email three times to be sure.",
];
const days = [
  "2026-03-02",
  "2026-03-20",
  "2026-04-08",
  "2026-05-01",
  "2026-05-22",
  "2026-06-12",
];
const labels = [
  "Mar 2, 2026",
  "Mar 20, 2026",
  "Apr 8, 2026",
  "May 1, 2026",
  "May 22, 2026",
  "Jun 12, 2026",
];

function entries(extra = {}) {
  return bodies.map((body, index) => ({
    id: `E${index + 1}`,
    role: "entry",
    date: labels[index],
    title: `Day ${index + 1}`,
    tags: index % 2 === 0 ? ["work", "hope"] : ["work"],
    firstTime: false,
    trimmed: false,
    passages: segmentPassages(body).map((p) => ({
      id: `E${index + 1}.P${p.id}`,
      text: p.text,
    })),
    ...extra,
  }));
}

const subject = {
  kind: "chapter",
  name: "Job search",
  span: "Mar - Jun 2026",
  note: null,
};
const selection = { entriesInPeriod: 6, entriesSent: 6, trimmedEntries: 0 };

function groundingContext(list = entries()) {
  return {
    entriesInPeriod: list.length,
    entries: new Map(
      list.map((entry, index) => {
        const body = bodies[index];
        const passages = segmentPassages(body);
        return [
          entry.id,
          {
            ref: entry.id,
            id: `entry-${index + 1}`,
            revision: 1,
            isNote: false,
            body,
            windowStart: days[index],
            windowEnd: null,
            passages: new Map(passages.map((p) => [p.id, p])),
            sentText: `${entry.title}\n${body}`,
          },
        ];
      }),
    ),
  };
}

const reviewInput = (list = entries(), language = "en") =>
  buildReviewInput({
    language,
    subject,
    selection,
    chapters: [],
    entries: list,
  });

const answer = (input) => JSON.parse(fakeAnswer(input).text);

describe("the fake review answer", () => {
  it("passes the real grounding checks for a Chapter review", () => {
    const review = resolveReview(answer(reviewInput()), groundingContext());
    expect(review.feelings.phases).toHaveLength(2);
    expect(review.feelings.phases[0].windowStart).toBe("2026-03-02");
    expect(review.themes.map((theme) => theme.name)).toContain("Work");
    expect(review.quotes).toHaveLength(4);
    expect(review.quotes[0].text).toBe("Sent the first application today.");
  });

  it("writes Chinese prose when asked and still grounds", () => {
    const text = reviewInput(entries(), "zh");
    const review = resolveReview(answer(text), groundingContext());
    expect(review.summary).toContain("记录");
  });

  it("adds a quote from a passage that does not exist for the bad-quote sentinel", () => {
    const list = entries();
    list[0].title = BAD_QUOTE_SENTINEL;
    const raw = answer(reviewInput(list));
    expect(raw.quotes.at(-1).from).toBe("E999.P1");
    // The server drops the unknown passage and keeps the four valid ones.
    expect(resolveReview(raw, groundingContext(list)).quotes).toHaveLength(4);
  });

  it("answers a map step in the shape the engine reads", () => {
    const text = buildMapInput({
      language: "en",
      subject,
      selection,
      chapters: [],
      entries: entries(),
      part: { index: 1, of: 2, dates: "Mar 2026 to Jun 2026" },
    });
    const map = resolveMap(answer(text), groundingContext());
    expect(map.arc.length).toBeGreaterThan(0);
    expect(map.quotes.length).toBeGreaterThan(0);
  });

  it("ends in a refusal for the refusal sentinel and fails for the outage sentinel", () => {
    const refused = entries();
    refused[1].title = REFUSAL_SENTINEL;
    expect(fakeAnswer(reviewInput(refused))).toMatchObject({
      status: 200,
      stopReason: "refusal",
      text: "",
    });
    const down = entries();
    down[2].title = OUTAGE_SENTINEL;
    expect(fakeAnswer(reviewInput(down)).status).toBe(529);
    expect(fakeAnswer("not json").status).toBe(400);
  });
});

describe("the fake suggestion answer", () => {
  const climbing = Array.from({ length: 14 }, (_, index) => {
    const month = ["Jul", "Aug", "Sep"][Math.floor(index / 5)];
    return {
      id: `S${index + 1}`,
      date: `${month} ${(index % 5) * 5 + 2}, 2026`,
      title: `Session ${index + 1}`,
      tags: ["climbing"],
      excerpt: "Went to the gym after work.",
      excerptOnly: true,
    };
  });
  const input = (extra = {}) =>
    buildChapterSuggestionInput({
      today: "2026-10-18",
      entries: climbing,
      existingChapters: [],
      earlierSuggestions: [],
      ...extra,
    });

  it("names the most common tag and passes the real validation", () => {
    const raw = answer(input({ today: "2026-12-18" }));
    expect(raw.suggestions).toHaveLength(1);
    expect(raw.suggestions[0]).toMatchObject({
      name: "Climbing",
      start: "2026-07",
      end: "2026-09",
    });
    const context = {
      today: "2026-12-18",
      entries: new Map(
        climbing.map((entry, index) => {
          const day = isoFor(entry.date);
          return [
            entry.id,
            {
              ref: entry.id,
              id: `entry-${index + 1}`,
              title: entry.title,
              excerpt: entry.excerpt,
              tags: entry.tags,
              dateLabel: entry.date,
              windowStart: day,
              windowEnd: addDay(day),
            },
          ];
        }),
      ),
      chapters: [],
      suggestions: [],
    };
    expect(validateSuggestions(raw, context)).toHaveLength(1);
  });

  it("leaves the end open while the newest Entry is recent and skips a named Chapter", () => {
    const recent = climbing.map((entry, index) => ({
      ...entry,
      date: `Oct ${index + 1}, 2026`,
    }));
    recent[0].date = "Aug 3, 2026";
    expect(answer(input({ entries: recent })).suggestions[0].end).toBeNull();
    expect(
      answer(
        input({ existingChapters: [{ name: "climbing", span: "Jul 2026" }] }),
      ).suggestions,
    ).toEqual([]);
  });

  it("proposes nothing when fewer than four Entries share a tag", () => {
    expect(
      answer(input({ entries: climbing.slice(0, 3) })).suggestions,
    ).toEqual([]);
  });
});

function isoFor(label) {
  return new Date(parseDateLabel(label)).toISOString().slice(0, 10);
}
function addDay(day) {
  return new Date(Date.parse(`${day}T00:00:00Z`) + 86_400_000)
    .toISOString()
    .slice(0, 10);
}

describe("date labels", () => {
  it("reads day, month, and year labels and refuses the rest", () => {
    expect(isoFor("Mar 14, 2026")).toBe("2026-03-14");
    expect(isoFor("Mar 2026")).toBe("2026-03-01");
    expect(isoFor("2026")).toBe("2026-01-01");
    expect(parseDateLabel("Date unknown")).toBeNull();
    expect(parseDateLabel("age 17")).toBeNull();
  });
});

describe("the fake AI server", () => {
  const fake = createFakeAIProvider({ apiKey: "test-key" });
  let url = "";
  beforeAll(async () => {
    url = await fake.start();
  });
  afterAll(() => fake.stop());

  const client = () =>
    new Anthropic({ apiKey: "test-key", baseURL: url, maxRetries: 0 });
  const ask = (input, key = "test-key") =>
    new Anthropic({ apiKey: key, baseURL: url, maxRetries: 0 }).messages
      .stream({
        model: "claude-sonnet-5-5",
        max_tokens: 100,
        system: "s",
        messages: [{ role: "user", content: input }],
      })
      .finalMessage();

  it("streams a message the Anthropic SDK reads", async () => {
    const input = reviewInput();
    const message = await ask(input);
    expect(message.stop_reason).toBe("end_turn");
    expect(message.model).toBe("claude-sonnet-5-5");
    expect(message.usage.input_tokens).toBeGreaterThan(
      Buffer.byteLength(input) / 4 - 1,
    );
    expect(message.usage.output_tokens).toBeGreaterThanOrEqual(50);
    const text = message.content.map((block) => block.text).join("");
    expect(JSON.parse(text).summary).toContain("6 Entries");
  });

  it("answers one JSON message when no stream is asked for", async () => {
    const message = await client().messages.create({
      model: "claude-sonnet-5-5",
      max_tokens: 100,
      messages: [{ role: "user", content: reviewInput() }],
    });
    expect(message.content[0].type).toBe("text");
  });

  it("reports a refusal, an outage, and a wrong key the way the provider does", async () => {
    const refused = entries();
    refused[0].title = REFUSAL_SENTINEL;
    expect((await ask(reviewInput(refused))).stop_reason).toBe("refusal");
    const down = entries();
    down[0].title = OUTAGE_SENTINEL;
    await expect(ask(reviewInput(down))).rejects.toMatchObject({ status: 529 });
    await expect(ask(reviewInput(), "wrong")).rejects.toMatchObject({
      status: 401,
    });
  });

  it("lists what it was sent, filtered by text and stage", async () => {
    const marked = entries();
    marked[0].title = "UNIQUE_MARKER_TITLE";
    await ask(reviewInput(marked));
    const list = await (
      await fetch(`${url}/__requests?contains=UNIQUE_MARKER_TITLE`)
    ).json();
    expect(list).toHaveLength(1);
    expect(list[0]).toMatchObject({
      stage: "review",
      model: "claude-sonnet-5-5",
      hasImages: false,
      status: 200,
    });
    expect(list[0].input).toContain("UNIQUE_MARKER_TITLE");
    expect(
      await (
        await fetch(`${url}/__requests?stage=map&contains=UNIQUE_MARKER_TITLE`)
      ).json(),
    ).toEqual([]);
    expect((await fetch(`${url}/nope`)).status).toBe(404);
  });
});
