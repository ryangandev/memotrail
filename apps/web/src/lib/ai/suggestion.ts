import { parseOrganizationNames } from "../data/inbox-review";
export type EntryAISuggestions = {
  title: string | null;
  classification: {
    itemKind: "event" | "writing";
    itemSubtype: "first_time" | "note";
  } | null;
  collections: string[];
  tags: string[];
  dateText: string | null;
  rationale: string;
  confidence: number;
};
export type EntryAISuggestionRecord = {
  id: string;
  entry_revision: number;
  status: "generating" | "proposed" | "applied" | "dismissed" | "failed";
  suggestions: EntryAISuggestions;
};
export type EntryAISuggestionResponse = {
  suggestion: EntryAISuggestionRecord | null;
  disabled?: boolean;
  photoCount?: number;
};
export function parseEntryAISuggestions(
  raw: unknown,
): EntryAISuggestions | null {
  if (!raw || typeof raw !== "object") return null;
  const v = raw as Record<string, unknown>;
  const collections = parseOrganizationNames(v.collections, 5, 80),
    tags = parseOrganizationNames(v.tags, 10, 60);
  if (
    !collections ||
    !tags ||
    (v.title !== null &&
      (typeof v.title !== "string" ||
        !v.title.trim() ||
        v.title.length > 200)) ||
    (v.classification !== null &&
      (!v.classification ||
        typeof v.classification !== "object" ||
        !("itemKind" in v.classification) ||
        !("itemSubtype" in v.classification) ||
        !(
          (v.classification.itemKind === "writing" &&
            v.classification.itemSubtype === "note") ||
          (v.classification.itemKind === "event" &&
            v.classification.itemSubtype === "first_time")
        ))) ||
    (v.dateText !== null &&
      (typeof v.dateText !== "string" || v.dateText.length > 200)) ||
    typeof v.rationale !== "string" ||
    v.rationale.length > 1000 ||
    typeof v.confidence !== "number" ||
    !Number.isFinite(v.confidence) ||
    v.confidence < 0 ||
    v.confidence > 1
  )
    return null;
  return {
    title: v.title === null ? null : (v.title as string).trim(),
    classification: v.classification as EntryAISuggestions["classification"],
    collections,
    tags,
    dateText: v.dateText as string | null,
    rationale: v.rationale,
    confidence: v.confidence,
  };
}
export function mergeAISuggestionNames(
  existing: string[],
  suggested: string[],
  limit: number,
) {
  const result = [...existing];
  for (const name of suggested)
    if (
      result.length < limit &&
      !result.some(
        (current) => current.toLocaleLowerCase() === name.toLocaleLowerCase(),
      )
    )
      result.push(name);
  return result.slice(0, limit);
}
