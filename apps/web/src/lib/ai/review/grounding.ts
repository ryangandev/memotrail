import { codePointLength, type Passage } from "./passages";

/**
 * A review is shown only if it can be checked against what the person wrote. The model picks
 * quotes by passage number and cites Entries by number; the server inserts the exact words,
 * drops anything that does not resolve, dates each phase from the Entries it cites, and
 * refuses a result with too little left. Themes and phases are interpretation, so what is
 * verified is that each one rests on real Entries from the period.
 */
export class GroundingError extends Error {
  constructor(public code: "invalid_review" | "ungrounded_review") {
    super(code);
  }
}

export type GroundingEntry = {
  /** `E0` for a Chapter's own note, otherwise `E1`, `E2`, and so on in time order. */
  ref: string;
  id: string;
  revision: number;
  isNote: boolean;
  body: string;
  /** The days the Entry stands for; `windowEnd` is exclusive and null when open-ended. */
  windowStart: string | null;
  windowEnd: string | null;
  /** The passages that were sent, by number. Empty where only notes were sent. */
  passages: ReadonlyMap<number, Passage>;
  /** Every word of the Entry the model could have seen, for checking quotation marks. */
  sentText: string;
};

export type Candidate = {
  from: string;
  to: string | null;
  ref: string;
  start: number;
  end: number;
  text: string;
};

export type GroundingContext = {
  entries: ReadonlyMap<string, GroundingEntry>;
  /** Entries dated inside the period, not counting a Chapter's note. */
  entriesInPeriod: number;
  /** For the final step of a long period: the only quotes it may choose. */
  candidates?: readonly Candidate[];
};

export type ReviewContent = {
  summary: string;
  feelings: {
    overview: string;
    phases: {
      feeling: string;
      description: string;
      entryIds: string[];
      windowStart: string;
      windowEnd: string;
    }[];
  };
  themes: { name: string; description: string; entryIds: string[] }[];
  quotes: {
    entryId: string;
    start: number;
    end: number;
    text: string;
    why: string;
  }[];
};

export type MapQuote = {
  from: string;
  to: string | null;
  ref: string;
  start: number;
  end: number;
  text: string;
  why: string;
};

export type MapResult = {
  notes: string;
  arc: { feeling: string; description: string; entries: string[] }[];
  themes: { name: string; description: string; entries: string[] }[];
  quotes: MapQuote[];
};

const LIMITS = {
  summary: 600,
  overview: 800,
  feeling: 60,
  phaseDescription: 600,
  themeName: 60,
  themeDescription: 500,
  why: 200,
  notes: 1500,
} as const;

const QUOTE_MIN = 8;
const QUOTE_MAX = 600;
const QUOTE_PASSAGES = 3;
const CITATIONS_MAX = 12;

export function parseModelJson(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    throw new GroundingError("invalid_review");
  }
}

const isObject = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

/** NFC-normalized and trimmed, or null when it is not a non-empty string within the limit. */
function field(value: unknown, max: number) {
  if (typeof value !== "string") return null;
  const clean = value.normalize("NFC").trim();
  if (clean === "" || codePointLength(clean) > max) return null;
  return clean;
}

function array(value: unknown): unknown[] {
  if (!Array.isArray(value)) throw new GroundingError("invalid_review");
  return value;
}

function required<T>(value: T | null): T {
  if (value === null) throw new GroundingError("invalid_review");
  return value;
}

const collapse = (text: string) => text.replace(/\s+/g, " ").trim();

const QUOTED = /"([^"]*)"|“([^”]*)”|「([^」]*)」|『([^』]*)』/g;

/**
 * Prose may not put words in quotation marks that the cited Entries do not contain, so an
 * invented quotation cannot hide inside an interpretation.
 */
export function quotationsHold(prose: string, evidence: readonly string[]) {
  const haystack = collapse(evidence.join("\n"));
  for (const match of prose.matchAll(QUOTED)) {
    const run = collapse(
      match.slice(1).find((part) => part !== undefined) ?? "",
    );
    if (run !== "" && !haystack.includes(run)) return false;
  }
  return true;
}

function citations(
  value: unknown,
  ctx: GroundingContext,
  options: { allowNote: boolean },
) {
  const refs: string[] = [];
  for (const item of array(value)) {
    if (typeof item !== "string" || !/^E\d+$/.test(item)) continue;
    const entry = ctx.entries.get(item);
    if (!entry || (entry.isNote && !options.allowNote) || refs.includes(item))
      continue;
    refs.push(item);
  }
  return refs.slice(0, CITATIONS_MAX);
}

function evidenceFor(refs: readonly string[], ctx: GroundingContext) {
  return refs.map((ref) => ctx.entries.get(ref)!.sentText);
}

function allEvidence(ctx: GroundingContext) {
  return [...ctx.entries.values()].map((entry) => entry.sentText);
}

function distinctDays(refs: readonly string[], ctx: GroundingContext) {
  return new Set(refs.map((ref) => ctx.entries.get(ref)!.windowStart)).size;
}

type PassageRef = { ref: string; number: number };
function passageRef(value: unknown): PassageRef | null {
  if (typeof value !== "string") return null;
  const match = /^(E\d+)\.P(\d+)$/.exec(value);
  return match ? { ref: match[1], number: Number(match[2]) } : null;
}

type ResolvedQuote = MapQuote;

function resolveQuote(
  raw: unknown,
  ctx: GroundingContext,
): ResolvedQuote | null {
  if (!isObject(raw)) return null;
  const why = field(raw.why, LIMITS.why);
  const from = passageRef(raw.from);
  const to =
    raw.to === null || raw.to === undefined ? null : passageRef(raw.to);
  if (!why || !from || (raw.to !== null && raw.to !== undefined && !to))
    return null;

  if (ctx.candidates) {
    const candidate = ctx.candidates.find(
      (item) => item.from === raw.from && item.to === (raw.to ?? null),
    );
    if (!candidate) return null;
    const entry = ctx.entries.get(candidate.ref);
    if (!entry || !entry.body.includes(candidate.text)) return null;
    const size = codePointLength(candidate.text);
    if (size < QUOTE_MIN || size > QUOTE_MAX) return null;
    return {
      from: candidate.from,
      to: candidate.to,
      ref: candidate.ref,
      start: candidate.start,
      end: candidate.end,
      text: candidate.text,
      why,
    };
  }

  const entry = ctx.entries.get(from.ref);
  if (!entry) return null;
  const last = to ?? from;
  if (
    last.ref !== from.ref ||
    last.number < from.number ||
    last.number - from.number + 1 > QUOTE_PASSAGES
  )
    return null;
  const first = entry.passages.get(from.number);
  const final = entry.passages.get(last.number);
  if (!first || !final) return null;
  // Every passage in between must have been sent as well.
  for (let number = from.number; number <= last.number; number += 1)
    if (!entry.passages.has(number)) return null;
  const text = Array.from(entry.body).slice(first.start, final.end).join("");
  const size = codePointLength(text);
  if (size < QUOTE_MIN || size > QUOTE_MAX || !entry.body.includes(text))
    return null;
  return {
    from: raw.from as string,
    to: to ? (raw.to as string) : null,
    ref: from.ref,
    start: first.start,
    end: final.end,
    text,
    why,
  };
}

function resolveQuotes(raw: unknown, ctx: GroundingContext, max: number) {
  const kept: ResolvedQuote[] = [];
  for (const item of array(raw)) {
    const quote = resolveQuote(item, ctx);
    if (!quote) continue;
    const entry = ctx.entries.get(quote.ref)!;
    if (!quotationsHold(quote.why, [entry.sentText])) continue;
    const overlaps = kept.some(
      (other) =>
        other.ref === quote.ref &&
        quote.start < other.end &&
        other.start < quote.end,
    );
    if (!overlaps) kept.push(quote);
  }
  return kept.slice(0, max);
}

function resolvePhases(raw: unknown, ctx: GroundingContext, max: number) {
  const phases: { feeling: string; description: string; refs: string[] }[] = [];
  for (const item of array(raw)) {
    if (!isObject(item)) continue;
    const feeling = field(item.feeling, LIMITS.feeling);
    const description = field(item.description, LIMITS.phaseDescription);
    if (!feeling || !description) continue;
    const refs = citations(item.entries, ctx, { allowNote: false });
    if (refs.length < 1) continue;
    const evidence = evidenceFor(refs, ctx);
    if (
      !quotationsHold(feeling, evidence) ||
      !quotationsHold(description, evidence)
    )
      continue;
    phases.push({ feeling, description, refs });
  }
  return phases.slice(0, max);
}

function resolveThemes(
  raw: unknown,
  ctx: GroundingContext,
  max: number,
  descriptionMax: number,
) {
  const themes: { name: string; description: string; refs: string[] }[] = [];
  for (const item of array(raw)) {
    if (!isObject(item)) continue;
    const name = field(item.name, LIMITS.themeName);
    const description = field(item.description, descriptionMax);
    if (!name || !description) continue;
    const refs = citations(item.entries, ctx, { allowNote: false });
    if (refs.length < 2 || distinctDays(refs, ctx) < 2) continue;
    const evidence = evidenceFor(refs, ctx);
    if (
      !quotationsHold(name, evidence) ||
      !quotationsHold(description, evidence)
    )
      continue;
    themes.push({ name, description, refs });
  }
  return themes.slice(0, max);
}

function addDay(day: string) {
  const date = new Date(`${day}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + 1);
  return date.toISOString().slice(0, 10);
}

/** The first day the cited Entries stand for through the last, so a phase never claims a date the Entries do not. */
function phaseWindow(refs: readonly string[], ctx: GroundingContext) {
  let start: string | null = null;
  let end: string | null = null;
  for (const ref of refs) {
    const entry = ctx.entries.get(ref)!;
    if (!entry.windowStart) continue;
    const last = entry.windowEnd ?? addDay(entry.windowStart);
    if (start === null || entry.windowStart < start) start = entry.windowStart;
    if (end === null || last > end) end = last;
  }
  return start && end ? { start, end } : null;
}

/** A full review, from one request or from the final step of a long period. */
export function resolveReview(
  raw: unknown,
  ctx: GroundingContext,
): ReviewContent {
  if (!isObject(raw) || !isObject(raw.feelings))
    throw new GroundingError("invalid_review");
  const summary = required(field(raw.summary, LIMITS.summary));
  const overview = required(field(raw.feelings.overview, LIMITS.overview));
  const everything = allEvidence(ctx);
  if (
    !quotationsHold(summary, everything) ||
    !quotationsHold(overview, everything)
  )
    throw new GroundingError("invalid_review");

  const phases = resolvePhases(raw.feelings.phases, ctx, 6)
    .flatMap((phase) => {
      const window = phaseWindow(phase.refs, ctx);
      return window ? [{ ...phase, window }] : [];
    })
    .map((phase, order) => ({ phase, order }))
    .sort(
      (a, b) =>
        (a.phase.window.start < b.phase.window.start
          ? -1
          : a.phase.window.start > b.phase.window.start
            ? 1
            : 0) || a.order - b.order,
    )
    .map(({ phase }) => phase);
  const themes = resolveThemes(raw.themes, ctx, 6, LIMITS.themeDescription);
  const order = [...ctx.entries.keys()];
  const quotes = resolveQuotes(raw.quotes, ctx, 10).sort(
    (a, b) => order.indexOf(a.ref) - order.indexOf(b.ref) || a.start - b.start,
  );

  const minimumThemes = ctx.entriesInPeriod >= 20 ? 2 : 1;
  const minimumQuotes = ctx.entriesInPeriod >= 10 ? 3 : 1;
  if (
    phases.length < 1 ||
    themes.length < minimumThemes ||
    quotes.length < minimumQuotes
  )
    throw new GroundingError("ungrounded_review");

  const id = (ref: string) => ctx.entries.get(ref)!.id;
  return {
    summary,
    feelings: {
      overview,
      phases: phases.map((phase) => ({
        feeling: phase.feeling,
        description: phase.description,
        entryIds: phase.refs.map(id),
        windowStart: phase.window.start,
        windowEnd: phase.window.end,
      })),
    },
    themes: themes.map((theme) => ({
      name: theme.name,
      description: theme.description,
      entryIds: theme.refs.map(id),
    })),
    quotes: quotes.map((quote) => ({
      entryId: id(quote.ref),
      start: quote.start,
      end: quote.end,
      text: quote.text,
      why: quote.why,
    })),
  };
}

/** Notes on one part of a long period, in the same terms, to be combined by the final step. */
export function resolveMap(raw: unknown, ctx: GroundingContext): MapResult {
  if (!isObject(raw)) throw new GroundingError("invalid_review");
  const notes = required(field(raw.notes, LIMITS.notes));
  if (!quotationsHold(notes, allEvidence(ctx)))
    throw new GroundingError("invalid_review");
  const arc = resolvePhases(raw.arc, ctx, 4).map((phase) => ({
    feeling: phase.feeling,
    description: phase.description,
    entries: phase.refs,
  }));
  const themes = resolveThemes(raw.themes, ctx, 5, LIMITS.themeDescription).map(
    (theme) => ({
      name: theme.name,
      description: theme.description,
      entries: theme.refs,
    }),
  );
  const quotes = resolveQuotes(raw.quotes, ctx, 12);
  if (arc.length < 1) throw new GroundingError("ungrounded_review");
  return { notes, arc, themes, quotes };
}
