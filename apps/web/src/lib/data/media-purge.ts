import type { SupabaseClient } from "@supabase/supabase-js";

export const MEDIA_PURGE_BATCH_SIZE = 100;

export const PENDING_MEDIA_PURGE_MESSAGE =
  "MemoTrail will finish removing private photo files the next time you open Trash.";

/**
 * Removes the Storage objects of permanently deleted photos.
 * Delete forever records them in the transaction that deletes the record, so this
 * only removes files nothing can restore. Any failure leaves them recorded for the
 * next attempt. Resolves whether nothing remains to remove.
 */
export async function finishMediaPurges(
  client: SupabaseClient,
  ownerId: string,
  maxRounds = 10,
): Promise<boolean> {
  try {
    for (let round = 0; round < maxRounds; round += 1) {
      const pending = await client.rpc("pending_media_purge_paths", {
        p_limit: MEDIA_PURGE_BATCH_SIZE,
      });
      if (
        pending.error ||
        !Array.isArray(pending.data) ||
        !pending.data.every(isObjectPathRow)
      )
        return false;
      const paths = [
        ...new Set(pending.data.map((row: ObjectPathRow) => row.object_path)),
      ];
      if (!paths.every((path) => isOwnedMediaPath(path, ownerId))) return false;
      if (paths.length > 0) {
        const removal = await client.storage.from("entry-media").remove(paths);
        if (removal.error) return false;
      }
      const completed = await client.rpc("complete_media_purges");
      if (completed.error || !Number.isSafeInteger(completed.data))
        return false;
      if (completed.data === 0) return true;
      // Recorded files that cannot be listed would never finish in this call.
      if (paths.length === 0) return false;
    }
  } catch {
    return false;
  }
  return false;
}

type ObjectPathRow = { object_path: string };

function isObjectPathRow(value: unknown): value is ObjectPathRow {
  return (
    typeof value === "object" &&
    value !== null &&
    typeof (value as { object_path?: unknown }).object_path === "string"
  );
}

function isOwnedMediaPath(path: string, ownerId: string) {
  const prefix = `${ownerId.toLowerCase()}/`;
  return (
    path.startsWith(prefix) &&
    path.length > prefix.length &&
    path.length <= 1024 &&
    !path.includes("..")
  );
}
