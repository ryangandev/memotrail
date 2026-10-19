import type { ImportSource } from "./types";

/** The words the import pages use, kept in one place so the page and the report agree. */
export const importLabels = {
  skippedKinds: {
    audio: "audio files",
    file: "other files",
    image_unsupported: "pictures in formats MemoTrail does not keep",
    pdf: "PDF files",
    photo_limit: "photos beyond the twelve an Entry holds",
    photo_too_large: "photos over 50 MB",
    video: "videos",
  } as Record<string, string>,
  reasons: {
    attempts_exceeded: "Stopped after repeated problems",
    changed_in_source: "Changed in the source since an earlier import",
    deleted_earlier: "Deleted forever earlier",
    empty: "Nothing to import",
    empty_entry: "Nothing to import",
    entry_deleted_forever: "Deleted forever earlier",
    entry_in_trash: "In Trash",
    file_too_large: "Text file too large",
    in_trash: "Already imported, now in Trash",
    invalid_entry: "MemoTrail could not save it",
    invalid_occurrence: "Its date could not be saved",
    invalid_rich_text: "Its formatting could not be saved",
    invalid_tags: "Its tags could not be saved",
    entry_content_too_long: "Too long",
    payload_missing: "Its text was no longer available",
    photo_conflict: "A photo clashed with an earlier one",
    photo_upload_failed: "Some photos did not upload",
    unexpected: "Something went wrong",
  } as Record<string, string>,
  sources: {
    apple_journal: "Apple Journal",
    apple_notes: "Apple Notes",
    day_one: "Day One",
    markdown: "Markdown folder",
    notion: "Notion",
  } satisfies Record<ImportSource, string>,
};

export function sourceLabel(source: ImportSource) {
  return importLabels.sources[source];
}
