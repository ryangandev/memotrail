/**
 * Splits an Entry into overlapping passages for embedding. Offsets are Unicode code
 * points into the plaintext body, matching Postgres `length()` and `substring()`, so a
 * stored range can later be sliced back out of the body as the "closest passage".
 */
export type EntryChunk = {
  end: number;
  index: number;
  start: number;
  text: string;
};

/** Passages target this many estimated tokens, never exceed the hard maximum. */
export const CHUNK_TARGET_TOKENS = 350;
export const CHUNK_MAX_TOKENS = 480;
export const CHUNK_MIN_TOKENS = 200;
export const CHUNK_OVERLAP_TOKENS = 60;
/** The database accepts at most this many chunks per Entry. */
export const MAX_CHUNKS_PER_ENTRY = 200;

const SENTENCE_END = new Set([".", "!", "?", "。", "！", "？", "；", ";", "…"]);
const CLOSERS = new Set([")", "”", "’", '"', "'", "」", "』", "）", "】"]);

/** A wide character (CJK, kana, hangul, emoji) is about one token; other text, a quarter. */
function tokenCost(character: string) {
  return (character.codePointAt(0) ?? 0) >= 0x2e80 ? 1 : 0.25;
}

function isWhitespace(character: string) {
  return /\s/u.test(character);
}

export function chunkEntryText(entry: {
  body: string;
  title: string | null;
}): EntryChunk[] {
  const characters = Array.from(entry.body);
  const length = characters.length;

  if (characters.every(isWhitespace)) {
    // A title still makes an Entry findable, as one chunk with an empty range.
    return entry.title?.trim()
      ? [{ end: 0, index: 0, start: 0, text: "" }]
      : [];
  }

  const costs = characters.map(tokenCost);
  const chunks: EntryChunk[] = [];
  let start = 0;

  while (start < length) {
    const lastChunk = chunks.length === MAX_CHUNKS_PER_ENTRY - 1;
    const hardEnd = lastChunk
      ? length
      : endWithin(costs, start, CHUNK_MAX_TOKENS);
    const end =
      hardEnd >= length
        ? length
        : chooseBoundary(characters, costs, start, hardEnd);

    pushTrimmed(chunks, characters, start, end);
    if (end >= length) break;
    start = overlapStart(characters, costs, start, end);
  }

  return chunks;
}

/** The largest end such that characters [start, end) cost at most `budget`. */
function endWithin(costs: number[], start: number, budget: number) {
  let total = 0;
  let end = start;
  while (end < costs.length && total + costs[end] <= budget) {
    total += costs[end];
    end += 1;
  }
  return Math.max(end, start + 1);
}

function chooseBoundary(
  characters: string[],
  costs: number[],
  start: number,
  hardEnd: number,
) {
  const targetEnd = endWithin(costs, start, CHUNK_TARGET_TOKENS);
  const earliest = Math.min(
    endWithin(costs, start, CHUNK_MIN_TOKENS),
    targetEnd,
  );
  const levels: Array<(position: number) => boolean> = [
    (position) =>
      characters[position - 1] === "\n" && characters[position - 2] === "\n",
    (position) => characters[position - 1] === "\n",
    (position) => endsSentence(characters, position),
    (position) => isWhitespace(characters[position - 1]),
  ];

  for (const matches of levels) {
    // Closest to the target: at or before it first, then the slack after it.
    for (let position = targetEnd; position >= earliest; position -= 1) {
      if (matches(position)) return position;
    }
    for (let position = targetEnd + 1; position <= hardEnd; position += 1) {
      if (matches(position)) return position;
    }
  }

  return targetEnd;
}

function endsSentence(characters: string[], position: number) {
  let last = position - 1;
  while (last > 0 && CLOSERS.has(characters[last])) last -= 1;
  return SENTENCE_END.has(characters[last]);
}

/** Where the next passage starts: about the overlap budget before the previous end. */
function overlapStart(
  characters: string[],
  costs: number[],
  previousStart: number,
  end: number,
) {
  let total = 0;
  let start = end;
  while (start > previousStart + 1 && total < CHUNK_OVERLAP_TOKENS) {
    start -= 1;
    total += costs[start];
  }
  // Begin Latin text at a word boundary instead of inside a word.
  for (let probe = start; probe < end; probe += 1) {
    if (isWhitespace(characters[probe - 1] ?? " ")) return probe;
    if (probe - start > 40) break;
  }
  return start;
}

function pushTrimmed(
  chunks: EntryChunk[],
  characters: string[],
  start: number,
  end: number,
) {
  let from = start;
  let to = end;
  while (from < to && isWhitespace(characters[from])) from += 1;
  while (to > from && isWhitespace(characters[to - 1])) to -= 1;
  if (from === to) return;
  chunks.push({
    end: to,
    index: chunks.length,
    start: from,
    text: characters.slice(from, to).join(""),
  });
}
