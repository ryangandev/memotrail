"use server";
import { revalidatePath } from "next/cache";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import {
  validOrganizationInput,
  type OrganizationInput,
} from "@/lib/data/organization";
export async function saveOrganization(
  input: OrganizationInput,
): Promise<string | null> {
  if (!validOrganizationInput(input))
    return "Use a name up to 80 characters and a valid whole-number order.";
  const context = await getAuthenticatedContext();
  if (!context) return "Sign in again to organize your archive.";
  const result = await context.client.rpc("save_organization", {
    p_kind: input.kind,
    p_name: input.name.trim(),
    p_sort_order: input.order,
    p_id: input.id,
    p_expected_revision: input.revision,
  });
  if (result.error?.code === "23505")
    return "This name already exists. Choose a different name; nothing was merged or overwritten.";
  if (result.error)
    return "Could not save. Your edits are still here to retry.";
  if (!result.data)
    return "This item changed on another device or moved to Trash. Reload before editing again.";
  revalidatePath("/", "layout");
  return null;
}
export async function trashCollection(
  input: OrganizationInput,
): Promise<string | null> {
  if (
    !validOrganizationInput(input) ||
    input.kind !== "collection" ||
    !input.id
  )
    return "Choose a valid Collection.";
  const context = await getAuthenticatedContext();
  if (!context) return "Sign in again to organize your archive.";
  const result = await context.client.rpc("trash_collection", {
    p_id: input.id,
    p_expected_revision: input.revision,
  });
  if (result.error)
    return "Could not move this Collection to Trash. Try again.";
  if (!result.data)
    return "This Collection changed on another device. Reload before trying again.";
  revalidatePath("/", "layout");
  return null;
}
