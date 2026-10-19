import { createServer } from "node:http";
import { fileURLToPath } from "node:url";

/**
 * A deterministic stand-in for the Anthropic Messages API, used only by tests. It answers
 * `POST /v1/messages` the way the SDK reads it (a server-sent event stream, or one JSON
 * message when the request does not ask for a stream) and writes fixed English prose with no
 * quotation marks, so what the app shows depends only on the Entries it sent. It never calls
 * a real model.
 *
 * Sentinels placed inside Entry text steer a single request:
 * - FAKE_AI_OUTAGE answers HTTP 529, the way an overloaded provider does.
 * - FAKE_AI_BAD_QUOTE adds a quote that points at a passage that does not exist.
 * - FAKE_AI_REFUSAL ends the answer with stop_reason "refusal".
 *
 * `GET /__requests` lists what the provider has been sent, so a test can assert what left the
 * app and what did not. `?contains=` keeps requests whose input holds that text, and
 * `?stage=` keeps one stage.
 */
export const OUTAGE_SENTINEL = "FAKE_AI_OUTAGE";
export const BAD_QUOTE_SENTINEL = "FAKE_AI_BAD_QUOTE";
export const REFUSAL_SENTINEL = "FAKE_AI_REFUSAL";

const MONTHS = [
  "jan",
  "feb",
  "mar",
  "apr",
  "may",
  "jun",
  "jul",
  "aug",
  "sep",
  "oct",
  "nov",
  "dec",
];
const DAY_MS = 86_400_000;

const isRow = (value) =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const isoDay = (ms) => new Date(ms).toISOString().slice(0, 10);

/** "Mar 14, 2026", "Mar 2026", or "2026" as a UTC day number, or null for any other label. */
export function parseDateLabel(label) {
  if (typeof label !== "string") return null;
  const match =
    /^(?:([A-Za-z]{3})[a-z]*\.? )?(?:(\d{1,2}), )?(\d{4})(?: |$)/.exec(
      label.trim(),
    );
  if (!match) return null;
  const month = match[1] ? MONTHS.indexOf(match[1].toLowerCase()) : 0;
  if (month < 0) return null;
  return Date.UTC(Number(match[3]), month, match[2] ? Number(match[2]) : 1);
}

/** Up to `limit` items spread evenly across a list, always including the first. */
function spread(items, limit) {
  if (items.length <= limit) return [...items];
  const picked = [];
  for (let i = 0; i < limit; i += 1)
    picked.push(items[Math.floor((i * items.length) / limit)]);
  return picked;
}

const capitalize = (text) =>
  text ? text[0].toUpperCase() + text.slice(1) : text;

const WORDS = {
  en: {
    early: "Getting started",
    later: "Settling in",
    earlyDescription:
      "The first Entries read as busy and a little unsure, with a lot to sort out.",
    laterDescription:
      "The later Entries read as steadier, with more room to notice small things.",
    overview:
      "Your feelings stayed fairly even through this period, with a gentler second half.",
    summary: (count, first, last) =>
      `This period held ${count} Entries, from ${first} to ${last}.`,
    theme: (tag) => `Entries tagged ${tag} come up on several different days.`,
    across: "Across the period",
    acrossDescription: "Similar concerns come up again in separate Entries.",
    why: "It says this part plainly.",
  },
  zh: {
    early: "刚刚开始",
    later: "渐渐安定",
    earlyDescription: "前面的记录比较忙碌，也有些不确定。",
    laterDescription: "后面的记录更平稳，也有余裕留意小事。",
    overview: "这段时间你的心情整体平稳，后半段更温和。",
    summary: (count, first, last) =>
      `这段时间共有${count}条记录，从${first}到${last}。`,
    theme: (tag) => `带有${tag}标签的记录在不同日子里反复出现。`,
    across: "贯穿始终",
    acrossDescription: "相似的关心在不同的记录里再次出现。",
    why: "这一段说得很直接。",
  },
};

function wordsFor(input) {
  return input.outputLanguage === "zh" ? WORDS.zh : WORDS.en;
}

/** Half-way split of Entries in time order into at most two phases. */
function phasesFor(entries, words) {
  const refs = entries.map((entry) => entry.id);
  if (refs.length === 0) return [];
  const half = Math.ceil(refs.length / 2);
  const phases = [
    {
      feeling: words.early,
      description: words.earlyDescription,
      entries: spread(refs.slice(0, half), 12),
    },
  ];
  if (refs.length > half)
    phases.push({
      feeling: words.later,
      description: words.laterDescription,
      entries: spread(refs.slice(half), 12),
    });
  return phases;
}

/** Themes from the most common tags, and one across the whole period when there is room. */
function themesFor(entries, words, limit) {
  const byTag = new Map();
  for (const entry of entries)
    for (const tag of Array.isArray(entry.tags) ? entry.tags : []) {
      if (typeof tag !== "string" || tag === "") continue;
      byTag.set(tag, [...(byTag.get(tag) ?? []), entry]);
    }
  const days = (list) => new Set(list.map((entry) => entry.date)).size;
  const themes = [...byTag.entries()]
    .filter(([, list]) => list.length >= 2 && days(list) >= 2)
    .sort((a, b) => b[1].length - a[1].length || (a[0] < b[0] ? -1 : 1))
    .slice(0, 3)
    .map(([tag, list]) => ({
      name: capitalize(tag),
      description: words.theme(tag),
      entries: spread(
        list.map((entry) => entry.id),
        12,
      ),
    }));
  if (themes.length < 2 && entries.length >= 2 && days(entries) >= 2)
    themes.push({
      name: words.across,
      description: words.acrossDescription,
      entries: spread(
        entries.map((entry) => entry.id),
        12,
      ),
    });
  return themes.slice(0, limit);
}

/** The first passage of each of the first Entries that has one long enough to quote. */
function quotesFor(entries, words, limit, input) {
  const quotes = [];
  for (const entry of entries) {
    if (quotes.length >= limit) break;
    const passages = Array.isArray(entry.passages) ? entry.passages : [];
    const passage = passages.find(
      (item) =>
        isRow(item) &&
        typeof item.id === "string" &&
        typeof item.text === "string" &&
        [...item.text].length >= 8 &&
        [...item.text].length <= 600,
    );
    if (passage) quotes.push({ from: passage.id, to: null, why: words.why });
  }
  if (JSON.stringify(input).includes(BAD_QUOTE_SENTINEL))
    quotes.push({ from: "E999.P1", to: null, why: words.why });
  return quotes;
}

function writtenEntries(input) {
  return (Array.isArray(input.entries) ? input.entries : []).filter(
    (entry) => isRow(entry) && entry.role !== "chapter_note",
  );
}

/** The whole review, from the Entries themselves. */
function reviewAnswer(input) {
  const words = wordsFor(input);
  const entries = writtenEntries(input);
  const first = entries[0]?.date ?? "";
  const last = entries.at(-1)?.date ?? "";
  return {
    summary: words.summary(entries.length, first, last),
    feelings: {
      overview: words.overview,
      phases: phasesFor(entries, words),
    },
    themes: themesFor(entries, words, 6),
    quotes: quotesFor(entries, words, 4, input),
  };
}

/** Notes on one part of a longer period. */
function mapAnswer(input) {
  const words = wordsFor(input);
  const entries = writtenEntries(input);
  return {
    notes: words.summary(
      entries.length,
      entries[0]?.date ?? "",
      entries.at(-1)?.date ?? "",
    ),
    arc: phasesFor(entries, words).slice(0, 2),
    themes: themesFor(entries, words, 5),
    quotes: quotesFor(entries, words, 4, input),
  };
}

/** The final review from the notes on each part and the candidate quotes. */
function reduceAnswer(input) {
  const words = wordsFor(input);
  const parts = Array.isArray(input.parts) ? input.parts : [];
  const arcs = parts.flatMap((part) =>
    Array.isArray(part?.arc) ? part.arc : [],
  );
  const merged = new Map();
  for (const part of parts)
    for (const theme of Array.isArray(part?.themes) ? part.themes : []) {
      if (!isRow(theme) || typeof theme.name !== "string") continue;
      const known = merged.get(theme.name) ?? {
        name: theme.name,
        description: theme.description,
        entries: [],
      };
      for (const ref of theme.entries ?? [])
        if (!known.entries.includes(ref)) known.entries.push(ref);
      merged.set(theme.name, known);
    }
  const candidates = Array.isArray(input.candidateQuotes)
    ? input.candidateQuotes
    : [];
  const entries = Array.isArray(input.entries) ? input.entries : [];
  return {
    summary: words.summary(
      entries.length,
      entries[0]?.date ?? "",
      entries.at(-1)?.date ?? "",
    ),
    feelings: {
      overview: words.overview,
      phases: spread(arcs, 6).map((phase) => ({
        feeling: phase.feeling,
        description: phase.description,
        entries: spread(phase.entries ?? [], 12),
      })),
    },
    themes: spread([...merged.values()], 6).map((theme) => ({
      ...theme,
      entries: spread(theme.entries, 12),
    })),
    quotes: spread(candidates, 8).map((candidate) => ({
      from: candidate.from,
      to: candidate.to ?? null,
      why: words.why,
    })),
  };
}

/**
 * Chapter suggestions: one per tag that at least four Entries share across three weeks or
 * more, the most common first. The app, not this fake, decides which are safe to show.
 */
function suggestionsAnswer(input) {
  const parsedToday =
    typeof input.today === "string" ? Date.parse(input.today) : NaN;
  const todayMs = Number.isFinite(parsedToday) ? parsedToday : Date.now();
  const existing = new Set(
    (Array.isArray(input.existingChapters) ? input.existingChapters : []).map(
      (chapter) => String(chapter?.name ?? "").toLowerCase(),
    ),
  );
  const byTag = new Map();
  for (const entry of Array.isArray(input.entries) ? input.entries : []) {
    const day = parseDateLabel(entry?.date);
    if (day === null || !entry.id) continue;
    for (const tag of Array.isArray(entry.tags) ? entry.tags : []) {
      if (typeof tag !== "string" || tag === "") continue;
      byTag.set(tag, [...(byTag.get(tag) ?? []), { id: entry.id, day }]);
    }
  }
  const suggestions = [];
  const groups = [...byTag.entries()].sort(
    (a, b) => b[1].length - a[1].length || (a[0] < b[0] ? -1 : 1),
  );
  for (const [tag, list] of groups) {
    if (suggestions.length >= 3) break;
    const days = list.map((item) => item.day);
    const firstDay = Math.min(...days);
    const lastDay = Math.max(...days);
    const name = capitalize(tag);
    if (
      list.length < 4 ||
      (lastDay - firstDay) / DAY_MS < 21 ||
      existing.has(name.toLowerCase())
    )
      continue;
    const ongoing = (todayMs - lastDay) / DAY_MS <= 45;
    suggestions.push({
      name,
      start: isoDay(firstDay).slice(0, 7),
      end: ongoing ? null : isoDay(lastDay).slice(0, 7),
      rationale: `Several of your Entries over these months centre on ${tag}.`,
      entries: list.slice(0, 20).map((item) => item.id),
    });
  }
  return { suggestions };
}

/** What the fake answers for one user message, and how that answer ends. */
export function fakeAnswer(inputText) {
  let input;
  try {
    input = JSON.parse(inputText);
  } catch {
    return { status: 400, error: "invalid_request_error" };
  }
  if (!isRow(input)) return { status: 400, error: "invalid_request_error" };
  if (inputText.includes(OUTAGE_SENTINEL))
    return { status: 529, error: "overloaded_error" };
  const stopReason = inputText.includes(REFUSAL_SENTINEL)
    ? "refusal"
    : "end_turn";
  const stage = typeof input.stage === "string" ? input.stage : null;
  let body;
  if (stopReason === "refusal") body = null;
  else if (stage === "review") body = reviewAnswer(input);
  else if (stage === "map") body = mapAnswer(input);
  else if (stage === "reduce") body = reduceAnswer(input);
  else if (!stage && "existingChapters" in input)
    body = suggestionsAnswer(input);
  else return { status: 400, error: "invalid_request_error" };
  return {
    status: 200,
    stage: stage ?? "suggestions",
    stopReason,
    text: body ? JSON.stringify(body) : "",
  };
}

function userText(message) {
  const content = message?.content;
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  return content
    .flatMap((block) =>
      isRow(block) && block.type === "text" && typeof block.text === "string"
        ? [block.text]
        : [],
    )
    .join("\n");
}

const sse = (event, data) =>
  `event: ${event}\ndata: ${JSON.stringify({ type: event, ...data })}\n\n`;

export function createFakeAIProvider({ apiKey } = {}) {
  const requests = [];
  let counter = 0;

  const server = createServer(async (request, response) => {
    const url = new URL(request.url ?? "/", "http://127.0.0.1");
    const send = (status, body) => {
      response.writeHead(status, { "Content-Type": "application/json" });
      response.end(JSON.stringify(body));
    };
    const fail = (status, type) =>
      send(status, {
        type: "error",
        error: { type, message: type },
      });

    if (request.method === "GET" && url.pathname === "/health")
      return send(200, { status: "ok" });
    if (request.method === "GET" && url.pathname === "/__requests") {
      const contains = url.searchParams.get("contains");
      const stage = url.searchParams.get("stage");
      return send(
        200,
        requests.filter(
          (item) =>
            (!contains || item.input.includes(contains)) &&
            (!stage || item.stage === stage),
        ),
      );
    }
    if (request.method !== "POST" || url.pathname !== "/v1/messages")
      return fail(404, "not_found_error");
    if (apiKey && request.headers["x-api-key"] !== apiKey)
      return fail(401, "authentication_error");

    let payload;
    let bytes;
    try {
      const chunks = [];
      for await (const chunk of request) chunks.push(chunk);
      bytes = Buffer.concat(chunks);
      payload = JSON.parse(bytes.toString("utf8"));
    } catch {
      return fail(400, "invalid_request_error");
    }
    const message = Array.isArray(payload?.messages)
      ? payload.messages.at(-1)
      : null;
    const input = userText(message);
    const answer = fakeAnswer(input);
    let stage = "unknown";
    try {
      const parsed = JSON.parse(input);
      stage =
        parsed.stage ??
        ("existingChapters" in parsed ? "suggestions" : "unknown");
    } catch {
      /* the request was malformed; it is still recorded below */
    }
    requests.push({
      model: payload?.model ?? null,
      stage,
      bytes: bytes.length,
      system: typeof payload?.system === "string" ? payload.system : "",
      input,
      hasImages: Array.isArray(message?.content)
        ? message.content.some((block) => block?.type === "image")
        : false,
      status: answer.status,
    });
    if (answer.status !== 200) return fail(answer.status, answer.error);

    const id = `msg_fake_${(counter += 1)}`;
    const model = typeof payload.model === "string" ? payload.model : "fake";
    const inputTokens = Math.ceil(bytes.length / 4);
    const outputTokens = Math.max(50, Math.ceil(answer.text.length / 4));
    const base = {
      id,
      type: "message",
      role: "assistant",
      model,
      stop_sequence: null,
    };
    if (payload.stream !== true)
      return send(200, {
        ...base,
        content: [{ type: "text", text: answer.text }],
        stop_reason: answer.stopReason,
        usage: { input_tokens: inputTokens, output_tokens: outputTokens },
      });

    response.writeHead(200, {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
    });
    response.write(
      sse("message_start", {
        message: {
          ...base,
          content: [],
          stop_reason: null,
          usage: { input_tokens: inputTokens, output_tokens: 1 },
        },
      }),
    );
    response.write(
      sse("content_block_start", {
        index: 0,
        content_block: { type: "text", text: "" },
      }),
    );
    // Two deltas, so a test also covers a message that arrives in pieces.
    const cut = Math.ceil(answer.text.length / 2);
    for (const text of [answer.text.slice(0, cut), answer.text.slice(cut)])
      if (text)
        response.write(
          sse("content_block_delta", {
            index: 0,
            delta: { type: "text_delta", text },
          }),
        );
    response.write(sse("content_block_stop", { index: 0 }));
    response.write(
      sse("message_delta", {
        delta: { stop_reason: answer.stopReason, stop_sequence: null },
        usage: { input_tokens: inputTokens, output_tokens: outputTokens },
      }),
    );
    response.write(sse("message_stop", {}));
    response.end();
  });

  return {
    /** Every Messages request seen so far, for assertions. */
    requests,
    async start(port = 0) {
      await new Promise((resolve) => server.listen(port, "127.0.0.1", resolve));
      return `http://127.0.0.1:${server.address().port}`;
    },
    async stop() {
      server.closeAllConnections?.();
      await new Promise((resolve) => server.close(resolve));
    },
  };
}

// `node scripts/fake-ai-provider.mjs [port] [api-key]` runs it by hand.
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const port = Number(process.argv[2] ?? 8789);
  const apiKey = process.argv[3] ?? "synthetic-e2e-key";
  const fake = createFakeAIProvider({ apiKey });
  const url = await fake.start(port);
  console.log(`Fake AI provider on ${url} (x-api-key ${apiKey})`);
}
