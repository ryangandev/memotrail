"use server";

import { revalidatePath } from "next/cache";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import {
  validOrganizationInput,
  type OrganizationInput,
  type TagEntryPreviewResult,
} from "@/lib/data/organization";
import { getTagEntryPreviews } from "@/lib/data/search";

type TagIdentity = { id: string; revision: number };

export async function loadTagEntryPreviews(
  tagName: string,
): Promise<TagEntryPreviewResult> {
  return getTagEntryPreviews(tagName);
}

export async function saveOrganization(
  input: OrganizationInput,
): Promise<string | null> {
  if (!validOrganizationInput(input)) {
    return input.kind === "tag"
      ? "Use a tag name up to 60 characters."
      : "Use a Collection name up to 80 characters and a valid whole-number order.";
  }
  const context = await getAuthenticatedContext();
  if (!context) return "Sign in again to organize your archive.";
  const result = await context.client.rpc("save_organization", {
    p_expected_revision: input.revision,
    p_id: input.id,
    p_kind: input.kind,
    p_name: input.name.trim(),
    p_sort_order: input.order,
  });
  if (result.error?.code === "23505") {
    return "This name already exists. Choose a different name; nothing was merged or overwritten.";
  }
  if (result.error)
    return "Could not save. Your edits are still here to retry.";
  if (!result.data) {
    return "This item changed on another device or moved to Trash. Refresh before editing again.";
  }
  refreshOrganizationPaths();
  return null;
}

export async function trashCollection(
  input: OrganizationInput,
): Promise<string | null> {
  if (
    !validOrganizationInput(input) ||
    input.kind !== "collection" ||
    !input.id
  ) {
    return "Choose a valid Collection.";
  }
  const context = await getAuthenticatedContext();
  if (!context) return "Sign in again to organize your archive.";
  const result = await context.client.rpc("trash_collection", {
    p_expected_revision: input.revision,
    p_id: input.id,
  });
  if (result.error)
    return "Could not move this Collection to Trash. Try again.";
  if (!result.data) {
    return "This Collection changed on another device. Refresh before trying again.";
  }
  refreshOrganizationPaths();
  return null;
}

export async function mergeTags(input: {
  source: TagIdentity;
  target: TagIdentity;
}): Promise<string | null> {
  if (
    !validTagIdentity(input.source) ||
    !validTagIdentity(input.target) ||
    input.source.id === input.target.id
  ) {
    return "Choose a different destination tag.";
  }
  const context = await getAuthenticatedContext();
  if (!context) return "Sign in again to organize your archive.";
  const result = await context.client.rpc("merge_tags", {
    p_source_id: input.source.id,
    p_source_revision: input.source.revision,
    p_target_id: input.target.id,
    p_target_revision: input.target.revision,
  });
  if (result.error) return "Could not merge these tags. Try again.";
  if (!result.data) {
    return "One of these tags changed on another device. Refresh before merging.";
  }
  refreshOrganizationPaths();
  return null;
}

export async function deleteUnusedTag(
  input: TagIdentity,
): Promise<string | null> {
  if (!validTagIdentity(input)) return "Choose a valid tag.";
  const context = await getAuthenticatedContext();
  if (!context) return "Sign in again to organize your archive.";
  const result = await context.client.rpc("delete_unused_tag", {
    p_expected_revision: input.revision,
    p_id: input.id,
  });
  if (result.error) return "Could not delete this tag. Try again.";
  if (!result.data) {
    return "This tag is still used by an Entry or changed elsewhere. Merge it or remove it from those Entries first.";
  }
  refreshOrganizationPaths();
  return null;
}

function validTagIdentity(value: TagIdentity) {
  return (
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
      value.id,
    ) &&
    Number.isSafeInteger(value.revision) &&
    value.revision > 0
  );
}

function refreshOrganizationPaths() {
  revalidatePath("/collections");
  revalidatePath("/inbox");
  revalidatePath("/search");
  revalidatePath("/tags");
  revalidatePath("/timeline");
}
