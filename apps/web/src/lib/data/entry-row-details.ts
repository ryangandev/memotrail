import "server-only";

import type { SupabaseClient } from "@supabase/supabase-js";
import { displayImageURLs } from "@/lib/media/urls";

/** What an EntryRow shows beyond the Entry's own fields: its first photo and its tags. */
export type EntryRowDetails = {
  photo: { alt: string; src: string | null } | null;
  tagNames: string[];
};

type PhotoRow = { entry_id: string; object_path: string };

type TagRow = { entry_id: string; tags: { name: string } | null };

/**
 * The first photo of each Entry, as a small thumbnail, and its tags when the list did not already
 * load them. A detail that cannot load leaves the row without it, since rows read fine without.
 */
export async function loadEntryRowDetails(
  client: SupabaseClient,
  entryIds: readonly string[],
  { tags = true }: { tags?: boolean } = {},
): Promise<Map<string, EntryRowDetails>> {
  const ids = [...new Set(entryIds)];
  const details = new Map<string, EntryRowDetails>(
    ids.map((id) => [id, { photo: null, tagNames: [] }]),
  );
  if (ids.length === 0) return details;

  const [photos, tagRows] = await Promise.all([
    client
      .from("attachments")
      .select("entry_id,object_path")
      .in("entry_id", ids)
      .eq("variant", "original")
      .eq("bucket_id", "entry-media")
      .is("deleted_at", null)
      .like("mime_type", "image/%")
      .order("created_at")
      .order("id")
      .returns<PhotoRow[]>(),
    tags
      ? client
          .from("entry_tags")
          .select("entry_id,tags(name)")
          .in("entry_id", ids)
          .returns<TagRow[]>()
      : Promise.resolve({ data: [] as TagRow[], error: null }),
  ]);

  const firstPhotos = new Map<string, PhotoRow>();
  for (const row of photos.error ? [] : (photos.data ?? [])) {
    if (!firstPhotos.has(row.entry_id)) firstPhotos.set(row.entry_id, row);
  }
  const urls = await displayImageURLs(
    client,
    [...firstPhotos.values()].map((row) => row.object_path),
  );
  for (const [entryId, row] of firstPhotos) {
    const url = urls.get(row.object_path);
    details.get(entryId)!.photo = {
      // The row's link already names the Entry, and a file name describes nothing.
      alt: "",
      src: url ? `${url}&variant=thumbnail` : null,
    };
  }

  for (const row of tagRows.error ? [] : (tagRows.data ?? [])) {
    const name = row.tags?.name;
    if (name) details.get(row.entry_id)?.tagNames.push(name);
  }
  for (const entry of details.values()) {
    entry.tagNames.sort((left, right) =>
      left.localeCompare(right, undefined, { sensitivity: "base" }),
    );
  }
  return details;
}

/** How many Entries each Chapter holds, for the line under a Chapter's row. */
export async function loadChapterEntryCounts(
  client: SupabaseClient,
  chapterIds: readonly string[],
): Promise<Map<string, number>> {
  const counts = new Map<string, number>();
  await Promise.all(
    [...new Set(chapterIds)].map(async (chapterId) => {
      const { data, error } = await client.rpc("chapter_entries", {
        p_chapter_id: chapterId,
        p_limit: 1,
        p_offset: 0,
      });
      if (error || !Array.isArray(data)) return;
      const count = Number(data[0]?.total_count ?? 0);
      if (Number.isSafeInteger(count)) counts.set(chapterId, count);
    }),
  );
  return counts;
}

/** "38 Entries", or null for an empty Chapter. */
export function chapterEntryCountLabel(count: number | undefined) {
  if (!count) return null;
  return `${count} ${count === 1 ? "Entry" : "Entries"}`;
}
