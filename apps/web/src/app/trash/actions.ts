"use server";

import { revalidatePath } from "next/cache";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import { parseEmptyTrashSnapshot } from "@/lib/data/empty-trash";
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
        error.code === "23505"
          ? "An active Collection already has this name. Rename it in organization settings, then restore this one."
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

export async function deleteTrashItemForever(
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

  const rpcInput = {
    p_expected_deleted_at: parsed.data.deletedAt,
    p_expected_revision: parsed.data.revision,
    p_item_id: parsed.data.itemId,
    p_item_kind: parsed.data.itemKind,
  };
  const pathResult = await context.client.rpc(
    "trash_item_storage_paths",
    rpcInput,
  );

  if (pathResult.error || !Array.isArray(pathResult.data)) {
    return {
      message: "MemoTrail could not verify this item's private photos.",
      status: "error",
    };
  }

  if (!pathResult.data.every(isObjectPathRow)) {
    return {
      message: "MemoTrail could not verify this item's private photos.",
      status: "error",
    };
  }

  const storagePaths = [
    ...new Set(pathResult.data.map((row) => row.object_path)),
  ];

  if (storagePaths.length > 0) {
    const { error } = await context.client.storage
      .from("entry-media")
      .remove(storagePaths);

    if (error) {
      return {
        message:
          "MemoTrail could not remove the private photos, so nothing else was deleted.",
        status: "error",
      };
    }
  }

  const { data, error } = await context.client.rpc(
    "delete_trash_item_forever",
    rpcInput,
  );

  if (error) {
    return {
      message:
        error.message === "media_cleanup_required"
          ? "A photo preview finished while this item was being removed. Refresh and try Delete forever again to remove the remaining files."
          : "MemoTrail could not permanently delete this item. Try again.",
      status: "error",
    };
  }

  if (!Array.isArray(data) || data.length === 0) {
    return changedItem();
  }

  refreshTrashPaths();
  return { message: "Item permanently deleted.", status: "deleted" };
}

function isObjectPathRow(value: unknown): value is { object_path: string } {
  return (
    typeof value === "object" &&
    value !== null &&
    typeof (value as { object_path?: unknown }).object_path === "string"
  );
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
    "/collections",
    "/tags",
    "/goals",
    "/first-times",
    "/homes",
    "/people",
    "/search",
    "/timeline",
    "/trash",
  ]) {
    revalidatePath(path);
  }
}
