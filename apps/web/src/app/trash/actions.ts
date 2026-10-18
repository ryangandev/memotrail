"use server";

import { revalidatePath } from "next/cache";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import { parseEmptyTrashSnapshot } from "@/lib/data/empty-trash";
import {
  finishMediaPurges,
  PENDING_MEDIA_PURGE_MESSAGE,
} from "@/lib/data/media-purge";
import {
  parseTrashItemInput,
  type TrashItemInput,
} from "@/lib/data/trash-input";

export type TrashActionResult = {
  message: string;
  status: "deleted" | "error" | "restored";
};

export async function prepareEmptyTrash(): Promise<
  { items: TrashItemInput[]; error: null } | { items: null; error: string }
> {
  const context = await getAuthenticatedContext();
  if (!context) return { items: null, error: expiredSession().message };
  const { data, error } = await context.client.rpc("prepare_empty_trash");
  const items = error ? null : parseEmptyTrashSnapshot(data);
  if (!items)
    return {
      items: null,
      error:
        error?.message === "trash_snapshot_too_large"
          ? "Trash contains more than 10,000 items. Remove some individually before reviewing Empty Trash."
          : "Could not prepare the complete Trash list. Nothing was deleted. Refresh and try again.",
    };
  return { items, error: null };
}

export async function restoreTrashItem(
  input: TrashItemInput,
): Promise<TrashActionResult> {
  const parsed = parseTrashItemInput(input);

  if (!parsed.success) {
    return { message: parsed.message, status: "error" };
  }

  const context = await getAuthenticatedContext();

  if (!context) {
    return expiredSession();
  }

  const { data, error } = await context.client.rpc("restore_trash_item", {
    p_expected_deleted_at: parsed.data.deletedAt,
    p_expected_revision: parsed.data.revision,
    p_item_id: parsed.data.itemId,
    p_item_kind: parsed.data.itemKind,
  });

  if (error) {
    return {
      message:
        error.message === "trash_media_unavailable"
          ? "This item's original photos are missing, so it cannot be restored. You can still delete it forever."
          : "MemoTrail could not restore this item. Try again.",
      status: "error",
    };
  }

  if (!Array.isArray(data) || data.length === 0) {
    return changedItem();
  }

  refreshTrashPaths();
  return { message: "Item restored.", status: "restored" };
}

/**
 * Deletes the record first, which records its private photo files for removal in
 * the same transaction. The files are removed next; anything left is retried the
 * next time Trash opens. Empty Trash finishes the files once after its batch.
 */
export async function deleteTrashItemForever(
  input: TrashItemInput,
  options: { finishCleanup?: boolean } = {},
): Promise<TrashActionResult> {
  const parsed = parseTrashItemInput(input);

  if (!parsed.success) {
    return { message: parsed.message, status: "error" };
  }

  const context = await getAuthenticatedContext();

  if (!context) {
    return expiredSession();
  }

  const { data, error } = await context.client.rpc(
    "delete_trash_item_forever",
    {
      p_expected_deleted_at: parsed.data.deletedAt,
      p_expected_revision: parsed.data.revision,
      p_item_id: parsed.data.itemId,
      p_item_kind: parsed.data.itemKind,
    },
  );

  if (error) {
    return {
      message: "MemoTrail could not permanently delete this item. Try again.",
      status: "error",
    };
  }

  if (!Array.isArray(data) || data.length === 0) {
    return changedItem();
  }

  refreshTrashPaths();
  const finished =
    options.finishCleanup === false ||
    (await finishMediaPurges(context.client, context.userId));
  return {
    message: finished
      ? "Item permanently deleted."
      : `Item permanently deleted. ${PENDING_MEDIA_PURGE_MESSAGE}`,
    status: "deleted",
  };
}

/** Removes the private photo files of everything already deleted forever. */
export async function finishTrashCleanup(): Promise<boolean> {
  const context = await getAuthenticatedContext();
  return context
    ? finishMediaPurges(context.client, context.userId, 100)
    : false;
}

function changedItem(): TrashActionResult {
  return {
    message:
      "This item changed on another device. Refresh before trying again.",
    status: "error",
  };
}

function expiredSession(): TrashActionResult {
  return {
    message: "Your session expired. Sign in again before making changes.",
    status: "error",
  };
}

function refreshTrashPaths() {
  for (const path of [
    "/",
    "/tags",
    "/first-times",
    "/homes",
    "/search",
    "/timeline",
    "/trash",
  ]) {
    revalidatePath(path);
  }
}
