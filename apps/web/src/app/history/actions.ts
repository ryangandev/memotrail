"use server";
import { revalidatePath } from "next/cache";
import { getAuthenticatedContext, entryFromRow } from "@/lib/data/inbox";
import {
  validHistoryID,
  validHistoryRestore,
  UNSUPPORTED_HISTORY_RESTORE_MESSAGE,
} from "@/lib/data/history";
import {
  parseGoalExtractionInput,
  type GoalExtractionInput,
} from "@/lib/data/goal-record-input";
import { existingLocationFromRow } from "@/lib/locations/location";

export async function loadEditableEntry(id: string) {
  if (!validHistoryID(id)) return null;
  const context = await getAuthenticatedContext();
  if (!context) return null;
  const [{ data, error }, tags] = await Promise.all([
    context.client.rpc("editable_entry", { p_entry_id: id }),
    context.client
      .from("tags")
      .select("name")
      .eq("owner_id", context.userId)
      .order("name"),
  ]);
  if (error || !data) return null;
  return {
    entry: entryFromRow(
      data,
      data.tag_names,
      existingLocationFromRow(data.primary_location),
    ),
    tagOptions: tags.error
      ? data.tag_names
      : (tags.data ?? []).map((tag) => tag.name),
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
      error: "Sign in again to add this to Want to Do.",
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
        "The source changed or is in Trash. Refresh before adding it to Want to Do.",
      goalId: null,
    };
  revalidatePath("/", "layout");
  return { error: null, goalId: result.goal_entry_id };
}
export async function restoreHistoryVersion(
  id: string,
  version: number,
  revision: number,
): Promise<string | null> {
  if (!validHistoryRestore(id, version, revision))
    return "Choose a valid earlier version.";
  const context = await getAuthenticatedContext();
  if (!context) return "Sign in again to restore history.";
  const { data, error } = await context.client.rpc("restore_entry_version", {
    p_entry_id: id,
    p_version: version,
    p_expected_revision: revision,
  });
  if (error?.message === "history_schema_unsupported")
    return UNSUPPORTED_HISTORY_RESTORE_MESSAGE;
  if (error?.message === "history_reference_unavailable")
    return "A linked item is missing or in Trash. Restore it first; no part of this Entry was changed.";
  if (error?.message === "history_attachment_unavailable")
    return "An original photo is no longer available. Nothing was restored.";
  if (error?.message === "history_details_unavailable")
    return "This early version did not record the specialized details needed for a safe restore.";
  if (error)
    return "Could not restore this version. Your current Entry is unchanged.";
  if (!data)
    return "This Entry changed on another device or is in Trash. Refresh or restore it from Trash first.";
  revalidatePath("/", "layout");
  return null;
}

export async function trashWikiItem(
  id: string,
  revision: number,
): Promise<string | null> {
  if (!validHistoryID(id) || !Number.isSafeInteger(revision) || revision < 1) {
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
