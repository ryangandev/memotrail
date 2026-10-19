export const tagNameCountLimit = 70;
export const tagNameLengthLimit = 80;
export const tagNamesLimitMessage = `Use up to ${tagNameCountLimit} tags with names up to ${tagNameLengthLimit} characters.`;

// Tags are unique regardless of case, so a typed name that differs from an existing tag
// only by case is that tag, written the way it already is.
export function existingTagName(name: string, options: readonly string[]) {
  const trimmed = name.trim();
  const normalized = trimmed.toLocaleLowerCase();
  return (
    options.find((option) => option.toLocaleLowerCase() === normalized) ??
    trimmed
  );
}

// The tags to save, including a name still typed in the tag field.
export function tagNamesIncludingDraft(
  names: string[],
  draft: string,
  options: readonly string[],
) {
  const name = existingTagName(draft, options);
  const normalized = name.toLocaleLowerCase();
  return !name || names.some((item) => item.toLocaleLowerCase() === normalized)
    ? names
    : [...names, name];
}

export type TagItem = {
  id: string;
  name: string;
  revision: number;
  entry_count: number;
  total_count: number;
};
export type TagInput = {
  id: string | null;
  revision: number | null;
  name: string;
};
export type TagEntryPreview = {
  /** Null when the title already is the date. */
  date: string | null;
  href: string;
  id: string;
  title: string;
  type: string;
};
export type TagEntryPreviewResult = {
  entries: TagEntryPreview[];
  error: string | null;
};

export function parseTagItems(value: unknown): TagItem[] | null {
  if (!Array.isArray(value)) return null;
  return value.every(isTagItem) ? value : null;
}

function isTagItem(value: unknown): value is TagItem {
  return (
    typeof value === "object" &&
    value !== null &&
    typeof (value as TagItem).id === "string" &&
    typeof (value as TagItem).name === "string" &&
    typeof (value as TagItem).revision === "number" &&
    (typeof (value as TagItem).entry_count === "number" ||
      typeof (value as TagItem).entry_count === "string") &&
    (typeof (value as TagItem).total_count === "number" ||
      typeof (value as TagItem).total_count === "string")
  );
}

/** A trimmed tag name that a tag could have, or null when no tag can be named this. */
export function validTagName(name: string) {
  const trimmed = name.trim();
  return trimmed && [...trimmed].length <= tagNameLengthLimit ? trimmed : null;
}

export function validTagInput(value: TagInput) {
  return (
    value &&
    typeof value.name === "string" &&
    validTagName(value.name) !== null &&
    (value.id === null
      ? value.revision === null
      : typeof value.id === "string" &&
        /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
          value.id,
        ) &&
        Number.isSafeInteger(value.revision) &&
        Number(value.revision) > 0)
  );
}
