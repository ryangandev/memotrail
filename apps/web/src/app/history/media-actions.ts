"use server";

import { getAuthenticatedContext } from "@/lib/data/inbox";
import { validHistoryID } from "@/lib/data/history";

export async function trashEntryPhoto(
  entryId: string,
  attachmentId: string,
): Promise<boolean> {
  if (!validHistoryID(entryId) || !validHistoryID(attachmentId)) return false;
  const context = await getAuthenticatedContext();
  if (!context) return false;
  const photo = await context.client
    .from("attachments")
    .select("id")
    .eq("id", attachmentId)
    .eq("entry_id", entryId)
    .eq("owner_id", context.viewer.id)
    .eq("variant", "original")
    .is("deleted_at", null)
    .maybeSingle();
  if (photo.error || !photo.data) return false;
  const { data, error } = await context.client.rpc("trash_entry_attachment", {
    p_attachment_id: attachmentId,
  });
  return (
    !error && Array.isArray(data) && data[0]?.attachment_id === attachmentId
  );
}
