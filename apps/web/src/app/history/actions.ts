"use server";
import { revalidatePath } from "next/cache";
import { getAuthenticatedContext, entryFromRow } from "@/lib/data/inbox";
import { validHistoryID } from "@/lib/data/history";
import { validHistoryRestore } from "@/lib/data/history";
import {
  parseGoalConversionInput,
  type GoalConversionInput,
} from "@/lib/data/goal-record-input";

export async function loadEditableEntry(id: string) {
  if (!validHistoryID(id)) return null;
  const context = await getAuthenticatedContext();
  if (!context) return null;
  const { data, error } = await context.client.rpc("editable_entry", {
    p_entry_id: id,
  });
  if (error || !data) return null;
  return {
    entry: entryFromRow(data, data.collection_names, data.tag_names),
    organized: data.inbox_status === "organized",
  };
}

export async function convertEntryToGoal(
  input: GoalConversionInput,
): Promise<string | null> {
  const parsed = parseGoalConversionInput(input);
  if (!parsed.success) return parsed.message;
  const context = await getAuthenticatedContext();
  if (!context) return "Sign in again to convert this Entry.";
  const value = parsed.data;
  const { data, error } = await context.client.rpc("convert_entry_to_goal", {
    p_entry_id: value.id,
    p_expected_revision: value.revision,
    p_title: value.title,
    p_horizon: value.horizon,
    p_status: value.status,
    p_target_date: value.targetDate,
  });
  if (error)
    return "Could not confirm conversion. Refresh to check the current Entry before retrying.";
  if (!data)
    return "This Entry changed, is in Trash, or is no longer Standard. Refresh before converting.";
  revalidatePath("/", "layout");
  return null;
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
