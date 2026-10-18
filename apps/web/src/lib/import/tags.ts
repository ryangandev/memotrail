import { importLimits } from "./limits";
import type { ImportCandidate, ImportOptions, ImportSource } from "./types";

/** The name of a tag from imported text: trimmed, one-spaced, no leading hash, within the limit. */
export function normalizeTagName(raw: string): string | null {
  const name = raw
    .replace(/\s+/g, " ")
    .trim()
    .replace(/^#+/, "")
    .trim()
    .slice(0, importLimits.tagChars)
    .trim();
  return name.length > 0 ? name : null;
}

/** Tag names without repeats, ignoring case, at most the number an Entry can hold. */
export function uniqueTagNames(names: readonly string[]): {
  names: string[];
  trimmed: boolean;
} {
  const seen = new Set<string>();
  const result: string[] = [];
  for (const raw of names) {
    const name = normalizeTagName(raw);
    if (!name) continue;
    const key = name.toLocaleLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    result.push(name);
  }
  return {
    names: result.slice(0, importLimits.tagsPerEntry),
    trimmed: result.length > importLimits.tagsPerEntry,
  };
}

export const sourceMarkerTags: Record<ImportSource, string> = {
  apple_journal: "Imported from Apple Journal",
  apple_notes: "Imported from Apple Notes",
  day_one: "Imported from Day One",
  markdown: "Imported from Markdown",
  notion: "Imported from Notion",
};

/** The tag that lists a whole import, and that Library can filter on. */
export function importMarkerTag(source: ImportSource) {
  return sourceMarkerTags[source];
}

/** The tag a folder gives its notes: the folder they sit directly in. */
export function folderTagName(folderPath: readonly string[]): string | null {
  const parent = folderPath.at(-1);
  return parent ? normalizeTagName(parent) : null;
}

/** Every tag an imported Entry gets, after the person's choices in the preview. */
export function entryTagNames(
  candidate: Pick<
    ImportCandidate,
    "tagNames" | "propertyTagNames" | "folderPath" | "source"
  >,
  options: Pick<ImportOptions, "tags">,
) {
  const names: string[] = [];
  if (options.tags.source) names.push(...candidate.tagNames);
  if (options.tags.properties) names.push(...candidate.propertyTagNames);
  if (options.tags.folders) {
    const folder = folderTagName(candidate.folderPath);
    if (folder) names.push(folder);
  }
  if (options.tags.marker) names.push(importMarkerTag(candidate.source));
  return uniqueTagNames(names);
}

export function defaultImportOptions(
  timezone: string,
  totals: { distinctParentFolders: number; notionDateProperty: string | null },
): ImportOptions {
  return {
    notionDateProperty: totals.notionDateProperty,
    tags: {
      // Many folders would add many tags, so the person turns them on knowingly.
      folders: totals.distinctParentFolders <= importLimits.maxFolderTags,
      marker: true,
      properties: true,
      source: true,
    },
    timezone,
    undated: "leave",
  };
}
