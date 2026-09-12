"use server";
import { revalidatePath } from "next/cache";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import { validHistoryRestore } from "@/lib/data/history";
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
