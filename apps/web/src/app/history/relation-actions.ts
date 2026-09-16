"use server";
import { revalidatePath } from "next/cache";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import {
  validRelationRequest,
  validRelationChange,
  type EntryRelations,
  type RelationRequest,
  type RelationChange,
} from "@/lib/data/entry-relations";
export async function loadEntryRelations(
  input: RelationRequest,
): Promise<EntryRelations> {
  if (!validRelationRequest(input)) throw Error("Invalid request");
  const context = await getAuthenticatedContext();
  if (!context) throw Error("Sign in required");
  const { data, error } = await context.client.rpc("entry_relations", {
    p_entry_id: input.entryID,
    p_mode: input.mode,
    p_query: input.query.trim(),
    p_limit: 20,
    p_offset: input.page * 20,
  });
  if (error || !data) throw Error("Relations unavailable");
  return data as EntryRelations;
}
export async function changeEntryRelation(
  input: RelationChange,
): Promise<string | null> {
  if (!validRelationChange(input)) return "Choose a different valid Item.";
  const context = await getAuthenticatedContext();
  if (!context) return "Sign in again to change links.";
  const { data, error } = await context.client.rpc("set_entry_relation", {
    p_entry_id: input.entryID,
    p_target_id: input.targetID,
    p_expected_revision: input.revision,
    p_linked: input.linked,
  });
  if (error?.message === "relation_limit")
    return "This Item already has 100 links. Remove a link before adding another.";
  if (error)
    return "Could not confirm this link change. Refresh before retrying.";
  if (!data)
    return "This Item changed or a linked Item is unavailable. Refresh before retrying.";
  revalidatePath("/", "layout");
  return null;
}
