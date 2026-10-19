"use server";
import { revalidatePath } from "next/cache";
import { getAuthenticatedContext, entryFromRow } from "@/lib/data/inbox";
import { validEntryID } from "@/lib/data/entry-detail";
import { existingLocationFromRow } from "@/lib/locations/location";
import { loadEntryPhotos } from "@/lib/data/entry-photos";
import { loadDefaultTimezone } from "@/lib/data/profile-timezone";
import { loadTagOptions } from "@/lib/data/tag-options";

export async function loadEditableEntry(id: string) {
  if (!validEntryID(id)) return null;
  const context = await getAuthenticatedContext();
  if (!context) return null;
  const [{ data, error }, tags, photos, defaultTimezone] = await Promise.all([
    context.client.rpc("editable_entry", { p_entry_id: id }),
    loadTagOptions(context.client, context.userId),
    loadEntryPhotos(context.client, context.userId, id),
    loadDefaultTimezone(context.client, context.userId),
  ]);
  if (error || !data || !photos) return null;
  return {
    defaultTimezone,
    entry: entryFromRow(
      data,
      data.tag_names,
      existingLocationFromRow(data.primary_location),
    ),
    photos: photos.photos,
    tagOptions: tags ?? data.tag_names,
  };
}

export async function trashWikiItem(
  id: string,
  revision: number,
): Promise<string | null> {
  if (!validEntryID(id) || !Number.isSafeInteger(revision) || revision < 1) {
    return "This item cannot be moved to Trash.";
  }

  const context = await getAuthenticatedContext();
  if (!context) return "Sign in again to move this item to Trash.";

  const { data, error } = await context.client
    .from("entries")
    .update({ deleted_at: new Date().toISOString() })
    .eq("id", id)
    .eq("revision", revision)
    .is("deleted_at", null)
    .select("id")
    .maybeSingle();

  if (error) return "MemoTrail could not move this item to Trash.";
  if (!data) {
    return "This item changed on another device or is already in Trash. Refresh and try again.";
  }

  revalidatePath("/", "layout");
  return null;
}
