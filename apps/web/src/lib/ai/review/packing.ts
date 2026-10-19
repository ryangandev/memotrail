import { codePointLength, segmentPassages, type Passage } from "./passages";

/**
 * Decides how much of a period one review reads and in how many requests.
 * Most periods fit one request. A larger one is read in consecutive parts (map steps) that a
 * final step combines (reduce). Only when even six full parts cannot hold the period are long
 * Entries shortened, and only after that are Entries left out, spread evenly across the period.
 * The estimates below decide packing only; budget reservations use UTF-8 bytes.
 */
export const SINGLE_PASS_TOKENS = 150_000;
export const SEGMENT_TOKENS = 110_000;
export const MAX_SEGMENTS = 6;
export const TRIM_CODE_POINTS = 6_000;
/** What the reduce step reads: notes on every part, never the Entries themselves. */
export const REDUCE_INPUT_TOKENS = 25_000;
const PASSAGE_OVERHEAD_TOKENS = 8;

export function estimateTokens(text: string) {
  const han = text.match(/\p{Script=Han}/gu)?.length ?? 0;
  const other = codePointLength(text) - han;
  return Math.ceil(han * 1.3 + other / 3) + 40;
}

export type PackableEntry = {
  id: string;
  isSubject: boolean;
  title: string;
  body: string;
  tags: readonly string[];
  isFirstTime: boolean;
};

export type PlannedStep = {
  index: number;
  kind: "review" | "map" | "reduce";
  entryIds: string[];
  /** What this step is expected to read, for the cost estimate only. */
  estimatedInputTokens: number;
};

export type Packed = {
  mode: "single" | "segmented";
  /** The Chapter's own note first when there is one, then the Entries read, oldest first. */
  entryIds: string[];
  noteEntryId: string | null;
  steps: PlannedStep[];
  /** Entries are read only up to this many code points when it is set. */
  trimCodePoints: number | null;
  /** Entries read in part. */
  trimmedEntries: number;
  /** Entries dated inside the period, not counting the Chapter's note. */
  entriesInPeriod: number;
  /** Entries actually read, not counting the Chapter's note. */
  entriesRead: number;
  estimatedInputTokens: number;
};

export type SentText = { passages: Passage[]; trimmed: boolean };

/** The passages of an Entry that are sent: all of them, or those within the first `trim` code points. */
export function sentPassages(body: string, trim: number | null): SentText {
  const all = segmentPassages(body);
  if (trim === null) return { passages: all, trimmed: false };
  const kept = all.filter((passage) => passage.end <= trim);
  return { passages: kept, trimmed: kept.length < all.length };
}

type Prepared = {
  entry: PackableEntry;
  full: { cost: number; trimmed: boolean };
  short: { cost: number; trimmed: boolean };
};

function costOf(entry: PackableEntry, trim: number | null) {
  const sent = sentPassages(entry.body, trim);
  const text = [entry.title, ...entry.tags, ...sent.passages.map((passage) => passage.text)].join("\n");
  return {
    cost: estimateTokens(text) + sent.passages.length * PASSAGE_OVERHEAD_TOKENS,
    trimmed: sent.trimmed,
  };
}

function prepare(entry: PackableEntry): Prepared {
  const full = costOf(entry, null);
  const short = costOf(entry, TRIM_CODE_POINTS);
  return { entry, full, short };
}

type Layout = { mode: "single" | "segmented"; segments: Prepared[][]; noteCost: number };

/** Consecutive parts, each within the limit. The note rides with the first part. */
function segment(items: Prepared[], trim: boolean, noteCost: number): Prepared[][] | null {
  const parts: Prepared[][] = [];
  let current: Prepared[] = [];
  let used = noteCost;
  for (const item of items) {
    const cost = trim ? item.short.cost : item.full.cost;
    if (cost > SEGMENT_TOKENS) return null;
    if (used + cost > SEGMENT_TOKENS && current.length > 0) {
      parts.push(current);
      current = [];
      used = 0;
    }
    current.push(item);
    used += cost;
  }
  if (current.length > 0 || parts.length === 0) parts.push(current);
  return parts.length <= MAX_SEGMENTS ? parts : null;
}

function layout(items: Prepared[], trim: boolean, noteCost: number): Layout | null {
  const total = noteCost + items.reduce((sum, item) => sum + (trim ? item.short.cost : item.full.cost), 0);
  if (total <= SINGLE_PASS_TOKENS) return { mode: "single", segments: [items], noteCost };
  const parts = segment(items, trim, noteCost);
  return parts ? { mode: "segmented", segments: parts, noteCost } : null;
}

/** Keeps exactly `k` of `n` positions, spread evenly. */
function evenly(n: number, k: number) {
  const kept: number[] = [];
  for (let i = 0; i < n; i += 1) {
    if (Math.floor(((i + 1) * k) / n) > Math.floor((i * k) / n)) kept.push(i);
  }
  return kept;
}

/** The largest count in [0, n] for which `fits` holds, assuming fewer always fits. */
function largest(n: number, fits: (count: number) => boolean) {
  let low = 0;
  let high = n;
  while (low < high) {
    const mid = Math.ceil((low + high) / 2);
    if (fits(mid)) low = mid;
    else high = mid - 1;
  }
  return low;
}

export function packPeriod(entries: readonly PackableEntry[]): Packed {
  const note = entries.find((entry) => entry.isSubject) ?? null;
  const prepared = entries.filter((entry) => !entry.isSubject).map(prepare);
  const noteCosts = note ? prepare(note) : null;
  const noteFull = noteCosts?.full.cost ?? 0;
  const noteShort = noteCosts?.short.cost ?? 0;

  let chosen: { kept: Prepared[]; plan: Layout; trim: boolean } | null = null;
  const whole = layout(prepared, false, noteFull);
  if (whole) chosen = { kept: prepared, plan: whole, trim: false };
  if (!chosen) {
    const shortened = layout(prepared, true, noteShort);
    if (shortened) chosen = { kept: prepared, plan: shortened, trim: true };
  }
  if (!chosen) {
    // Keep every First Time and spread the rest evenly, as many as fit.
    const firstTimes = prepared.filter((item) => item.entry.isFirstTime);
    const others = prepared.filter((item) => !item.entry.isFirstTime);
    const build = (protectedCount: number, otherCount: number) => {
      const protectedKept = evenly(firstTimes.length, protectedCount).map((i) => firstTimes[i]);
      const otherKept = evenly(others.length, otherCount).map((i) => others[i]);
      const keep = new Set([...protectedKept, ...otherKept]);
      return prepared.filter((item) => keep.has(item));
    };
    const withAllFirstTimes = (count: number) =>
      layout(build(firstTimes.length, count), true, noteShort);
    let protectedCount = firstTimes.length;
    let otherCount = 0;
    if (withAllFirstTimes(0)) {
      otherCount = largest(others.length, (count) => withAllFirstTimes(count) !== null);
    } else {
      protectedCount = largest(
        firstTimes.length,
        (count) => layout(build(count, 0), true, noteShort) !== null,
      );
    }
    const kept = build(protectedCount, otherCount);
    chosen = { kept, plan: layout(kept, true, noteShort)!, trim: true };
  }

  const { kept, plan, trim } = chosen;
  const cost = (item: Prepared) => (trim ? item.short.cost : item.full.cost);
  const noteCost = trim ? noteShort : noteFull;
  const noteIds = note ? [note.id] : [];
  const steps: PlannedStep[] = [];
  if (plan.mode === "single") {
    steps.push({
      index: 0,
      kind: "review",
      entryIds: [...noteIds, ...kept.map((item) => item.entry.id)],
      estimatedInputTokens: noteCost + kept.reduce((sum, item) => sum + cost(item), 0),
    });
  } else {
    plan.segments.forEach((part, index) => {
      steps.push({
        index,
        kind: "map",
        entryIds: [...(index === 0 ? noteIds : []), ...part.map((item) => item.entry.id)],
        estimatedInputTokens:
          (index === 0 ? noteCost : 0) + part.reduce((sum, item) => sum + cost(item), 0),
      });
    });
    steps.push({
      index: plan.segments.length,
      kind: "reduce",
      entryIds: [],
      estimatedInputTokens: REDUCE_INPUT_TOKENS,
    });
  }

  return {
    mode: plan.mode,
    entryIds: [...noteIds, ...kept.map((item) => item.entry.id)],
    noteEntryId: note?.id ?? null,
    steps,
    trimCodePoints: trim ? TRIM_CODE_POINTS : null,
    trimmedEntries: trim ? kept.filter((item) => item.short.trimmed).length : 0,
    entriesInPeriod: prepared.length,
    entriesRead: kept.length,
    estimatedInputTokens: steps.reduce((sum, step) => sum + step.estimatedInputTokens, 0),
  };
}

/** Output allowances per step kind, also used for the up-front cost estimate. */
export const STEP_MAX_TOKENS = { review: 16_000, reduce: 16_000, map: 10_000 } as const;

/** What a whole job could cost at most, in micro-dollars: the largest each request may bill. */
export function estimateJobMicros(
  steps: readonly PlannedStep[],
  price: { inputMicros: number; outputMicros: number },
) {
  return steps.reduce(
    (sum, step) =>
      sum +
      step.estimatedInputTokens * price.inputMicros +
      STEP_MAX_TOKENS[step.kind] * price.outputMicros,
    0,
  );
}
