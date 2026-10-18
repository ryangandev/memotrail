"use server";
import { revalidatePath } from "next/cache";
import { getAuthenticatedContext, entryFromRow } from "@/lib/data/inbox";
import { validEntryID } from "@/lib/data/entry-detail";
import {
  parseGoalExtractionInput,
  type GoalExtractionInput,
} from "@/lib/data/goal-record-input";
import { existingLocationFromRow } from "@/lib/locations/location";
import { milestoneFromRow } from "@/lib/data/milestone";
import { loadEntryPhotos } from "@/lib/data/entry-photos";
import { storedProfileTimezone } from "@/lib/data/profile-input";
import { loadTagOptions } from "@/lib/data/tag-options";

export async function loadEditableEntry(id: string) {
  if (!validEntryID(id)) return null;
  const context = await getAuthenticatedContext();
  if (!context) return null;
  const [{ data, error }, tags, photos, profile] = await Promise.all([
    context.client.rpc("editable_entry", { p_entry_id: id }),
    loadTagOptions(context.client, context.userId),
    loadEntryPhotos(context.client, context.userId, id),
    context.client
      .from("profiles")
      .select("timezone")
      .eq("user_id", context.userId)
      .single(),
  ]);
  if (error || !data || !photos) return null;
  const profileTimezone = storedProfileTimezone(
    profile.error ? null : profile.data,
  );
  return {
    // Without the Settings time zone, the editor shows every Entry's zone in full.
    defaultTimezone: profileTimezone.available
      ? profileTimezone.timezone
      : undefined,
    entry: {
      ...entryFromRow(
        data,
        data.tag_names,
        existingLocationFromRow(data.primary_location),
      ),
      milestone: milestoneFromRow(data.milestone),
    },
    photos: photos.photos,
    tagOptions: tags ?? data.tag_names,
  };
}

export async function extractGoalFromItem(
  input: GoalExtractionInput,
): Promise<{ error: string | null; goalId: string | null }> {
  const parsed = parseGoalExtractionInput(input);
  if (!parsed.success) return { error: parsed.message, goalId: null };
  const context = await getAuthenticatedContext();
  if (!context)
    return {
      error: "Sign in again to add this to Someday.",
      goalId: null,
    };
  const value = parsed.data;
  const { data, error } = await context.client.rpc("extract_goal_from_item", {
    p_goal_id: value.goalId,
    p_title: value.title,
    p_status: "active",
    p_target_date: value.targetDate,
    p_source_entry_id: value.sourceId,
    p_source_revision: value.sourceRevision,
  });
  if (error)
    return {
      error:
        "Could not confirm it was added. Refresh to check the source before retrying.",
      goalId: null,
    };
  const result = Array.isArray(data) ? data[0] : data;
  if (!result?.goal_entry_id)
    return {
      error:
        "The source changed or is in Trash. Refresh before adding it to Someday.",
      goalId: null,
    };
  revalidatePath("/", "layout");
  return { error: null, goalId: result.goal_entry_id };
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
