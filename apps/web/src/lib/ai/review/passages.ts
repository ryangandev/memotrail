/**
 * An Entry is shown to the model as numbered passages, and the model picks quotes by passage
 * number, never by retyping words. Offsets are in code points, so they agree with SQL `substr`
 * on a UTF-8 database, and `text` is always exactly `Array.from(body).slice(start, end)`.
 */
export type Passage = {
  /** 1-based number within the Entry. */
  id: number;
  /** Code point offsets into the Entry body, `end` exclusive. */
  start: number;
  end: number;
  text: string;
};

const MIN_PIECE = 12;
const LONG_PIECE = 400;
const SPLIT_WINDOW = 300;
const SPLIT_MARKS = new Set(["，", "、", ",", ";", "；", "：", ":"]);

type Piece = { start: number; end: number };

const isSpace = (character: string) => /^\s$/u.test(character);

function trimmed(cps: string[], piece: Piece): Piece | null {
  let { start, end } = piece;
  while (start < end && isSpace(cps[start])) start += 1;
  while (end > start && isSpace(cps[end - 1])) end -= 1;
  return start < end ? { start, end } : null;
}

function sentencePieces(cps: string[], paragraph: Piece): Piece[] {
  const text = cps.slice(paragraph.start, paragraph.end).join("");
  // Map UTF-16 offsets from the segmenter back to code point offsets.
  const offsets: number[] = [];
  let point = 0;
  for (let unit = 0; unit < text.length;) {
    offsets[unit] = point;
    const code = text.codePointAt(unit)!;
    const width = code > 0xffff ? 2 : 1;
    if (width === 2) offsets[unit + 1] = point;
    unit += width;
    point += 1;
  }
  offsets[text.length] = point;
  const segmenter = new Intl.Segmenter(undefined, { granularity: "sentence" });
  const pieces: Piece[] = [];
  for (const { index, segment } of segmenter.segment(text)) {
    pieces.push({
      start: paragraph.start + offsets[index],
      end: paragraph.start + offsets[index + segment.length],
    });
  }
  return pieces;
}

function splitLong(cps: string[], piece: Piece): Piece[] {
  const result: Piece[] = [];
  let rest: Piece | null = piece;
  while (rest && rest.end - rest.start > LONG_PIECE) {
    let cut = -1;
    for (let at = rest.start + SPLIT_WINDOW - 1; at > rest.start; at -= 1) {
      if (SPLIT_MARKS.has(cps[at]) || isSpace(cps[at])) {
        cut = at + 1;
        break;
      }
    }
    if (cut === -1) cut = rest.start + SPLIT_WINDOW;
    const head = trimmed(cps, { start: rest.start, end: cut });
    if (head) result.push(head);
    rest = trimmed(cps, { start: cut, end: rest.end });
  }
  if (rest) result.push(rest);
  return result;
}

export function segmentPassages(body: string): Passage[] {
  const cps = Array.from(body);
  const paragraphs: Piece[] = [];
  let from = 0;
  for (let at = 0; at <= cps.length; at += 1) {
    if (at === cps.length || cps[at] === "\n") {
      if (at > from) paragraphs.push({ start: from, end: at });
      from = at + 1;
    }
  }

  const pieces: Piece[] = [];
  for (const paragraph of paragraphs) {
    const sentences = sentencePieces(cps, paragraph).flatMap((piece) => {
      const clean = trimmed(cps, piece);
      return clean ? [clean] : [];
    });
    // A very short piece joins the next one in its paragraph, or the previous one at the end.
    const merged: Piece[] = [];
    let carry: Piece | null = null;
    for (const piece of sentences) {
      const joined: Piece = carry
        ? { start: carry.start, end: piece.end }
        : piece;
      carry = null;
      if (joined.end - joined.start < MIN_PIECE) carry = joined;
      else merged.push(joined);
    }
    if (carry) {
      const previous = merged.pop();
      merged.push(previous ? { start: previous.start, end: carry.end } : carry);
    }
    for (const piece of merged) pieces.push(...splitLong(cps, piece));
  }

  return pieces.map((piece, index) => ({
    id: index + 1,
    start: piece.start,
    end: piece.end,
    text: cps.slice(piece.start, piece.end).join(""),
  }));
}

/** The number of code points in `text`. */
export function codePointLength(text: string) {
  return Array.from(text).length;
}
