/** How a quick-search result matched: its words, its meaning, or both. */
export type QuickMatchedBy = "both" | "meaning" | "words";

export const MEANING_REASON = "Meaning";

const PASSAGE_LIMIT = 200;

export function matchedByFromReasons(
  reasons: readonly string[],
): QuickMatchedBy {
  const meaning = reasons.includes(MEANING_REASON);
  const words = reasons.some((reason) => reason !== MEANING_REASON);
  if (meaning && words) return "both";
  return meaning ? "meaning" : "words";
}

/**
 * The part of a long Entry that matched by meaning, cut from its body by the stored
 * code point range. A one-chunk Entry returns null: its card already shows its start.
 */
export function matchPassage(
  body: string,
  start: number | null,
  end: number | null,
  chunkCount: number | null,
): string | null {
  if (start === null || end === null || chunkCount === null) return null;
  if (chunkCount <= 1) return null;

  const characters = Array.from(body);
  if (!Number.isInteger(start) || !Number.isInteger(end)) return null;
  if (start < 0 || end < start || end > characters.length) return null;

  const excerpt = characters
    .slice(start, end)
    .join("")
    .replace(/\s+/g, " ")
    .trim();
  if (!excerpt) return null;

  const clipped = Array.from(excerpt);
  const truncated = clipped.length > PASSAGE_LIMIT;
  const text = truncated
    ? clipped.slice(0, PASSAGE_LIMIT).join("").trimEnd()
    : excerpt;
  const leading = start > 0 ? "..." : "";
  const trailing = truncated || end < characters.length ? "..." : "";
  return `${leading}${text}${trailing}`;
}

/** The Command Palette's second line for a quick result. */
export function quickResultDescription(item: {
  label: string;
  matchedBy: QuickMatchedBy;
  subtitle: string;
}) {
  return item.matchedBy === "meaning"
    ? `${item.label} · Meaning · ${item.subtitle}`
    : `${item.label} · ${item.subtitle}`;
}
