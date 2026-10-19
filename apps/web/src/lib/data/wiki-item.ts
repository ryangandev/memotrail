// Every item is an Entry. A Chapter is an Entry whose subtype is "chapter", and a First Time is
// an Entry marked `is_first_time`; both marks can sit on the same Entry.
export const wikiItemKinds = ["entry"] as const;

export type WikiItemKind = (typeof wikiItemKinds)[number];

/** The Library Record filter: Entries, Chapters, and First Times. */
export const wikiItemRecordFilters: readonly {
  label: string;
  value: string;
}[] = [
  { label: "Entries", value: "entry" },
  { label: "Chapters", value: "chapter" },
  { label: "First Times", value: "first_time" },
] as const;

export function isWikiItemKind(value: unknown): value is WikiItemKind {
  return (
    typeof value === "string" && wikiItemKinds.includes(value as WikiItemKind)
  );
}

export function wikiItemSubtypeLabel(subtype: string) {
  return subtype === "chapter" ? "Chapter" : "Entry";
}

/** What an item is called in a heading or badge: "Chapter · First Time", "Chapter", "First Time", or "Entry". */
export function wikiItemIdentityLabel(subtype: string, isFirstTime = false) {
  const isChapter = subtype === "chapter";
  if (isChapter && isFirstTime) return "Chapter · First Time";
  if (isChapter) return "Chapter";
  if (isFirstTime) return "First Time";
  return "Entry";
}

/** Every item opens on its Item page. */
export function wikiEntryHref(item: { id: string }) {
  return `/items/${item.id}`;
}
