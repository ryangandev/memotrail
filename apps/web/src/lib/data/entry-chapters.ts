import "server-only";

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  entryDisplayTitle,
  storedOccurrence,
  type Occurrence,
} from "./occurrence";
import { chaptersContaining } from "./occurrence-window";

/** A Chapter an Entry falls inside, as the Entry's page names it. */
export type EntryChapter = {
  id: string;
  occurrence: Occurrence;
  /** Its title, or its date when it has none. */
  title: string;
};

type ChapterRow = {
  date_precision: string;
  id: string;
  occurred_end: string | null;
  occurred_label: string | null;
  occurred_start: string | null;
  occurred_timezone: string | null;
  title: string | null;
};

/** The most Chapters one account is read for; more than this is far past real use. */
const chapterLimit = 500;

/**
 * The Chapters whose days hold every day of an Entry, innermost first, by the rule a Chapter's page
 * lists its Entries with. Null when they could not be read, so the page leaves the row out.
 */
export async function loadEntryChapters(
  client: SupabaseClient,
  ownerId: string,
  entry: Occurrence,
): Promise<EntryChapter[] | null> {
  if (!entry.occurredAt || entry.datePrecision === "unknown") return [];
  const { data, error } = await client
    .from("entries")
    .select(
      "id,title,occurred_start,occurred_end,date_precision,occurred_label,occurred_timezone",
    )
    .eq("owner_id", ownerId)
    .eq("item_subtype", "chapter")
    .is("deleted_at", null)
    .not("occurred_start", "is", null)
    .limit(chapterLimit);
  if (error || !Array.isArray(data)) return null;
  const chapters = (data as ChapterRow[]).map((row) => {
    const occurrence = storedOccurrence({
      datePrecision: row.date_precision,
      occurredEnd: row.occurred_end,
      occurredLabel: row.occurred_label,
      occurredStart: row.occurred_start,
      occurredTimezone: row.occurred_timezone,
    });
    return {
      id: row.id,
      occurrence,
      title: entryDisplayTitle(row.title, occurrence),
    };
  });
  return chaptersContaining(entry, chapters);
}
