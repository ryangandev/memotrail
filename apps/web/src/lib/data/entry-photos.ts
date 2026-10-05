import "server-only";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { EntryPhoto } from "@/lib/media/photo-metadata";
import { displayImageURLs } from "@/lib/media/urls";

const entryPhotoPageSize = 100;

export type EntryPhotos = { hasMore: boolean; photos: EntryPhoto[] };

// An Entry's current photos, oldest first, with short-lived display URLs. The caller
// confirms the Entry is the owner's; the query also runs as the verified owner.
export async function loadEntryPhotos(
  client: SupabaseClient,
  ownerId: string,
  entryId: string,
): Promise<EntryPhotos | null> {
  const { data, error } = await client
    .from("attachments")
    .select("id,original_filename,object_path")
    .eq("entry_id", entryId)
    .eq("owner_id", ownerId)
    .eq("variant", "original")
    .eq("bucket_id", "entry-media")
    .is("deleted_at", null)
    .order("created_at")
    .order("id")
    .limit(entryPhotoPageSize + 1);
  if (error) return null;
  const rows = (data ?? []).slice(0, entryPhotoPageSize);
  const urls = await displayImageURLs(
    client,
    rows.map((row) => row.object_path),
  );
  return {
    hasMore: (data ?? []).length > entryPhotoPageSize,
    photos: rows.map((row) => ({
      id: row.id,
      imageUrl: urls.get(row.object_path) ?? null,
      name: row.original_filename ?? "Photo",
    })),
  };
}
