import { parseTrashItemInput, type TrashItemInput } from "./trash-input";
import { countLabel } from "@/lib/count-label";
import { PENDING_MEDIA_PURGE_MESSAGE } from "./media-purge";

export function parseEmptyTrashSnapshot(
  value: unknown,
): TrashItemInput[] | null {
  if (!Array.isArray(value) || value.length > 10000) return null;
  const items: TrashItemInput[] = [];
  const seen = new Set<string>();
  for (const row of value) {
    if (!row || typeof row !== "object") return null;
    const parsed = parseTrashItemInput({
      itemId: row.item_id,
      itemKind: row.item_kind,
      deletedAt: row.deleted_at,
      revision: row.revision,
    });
    if (!parsed.success) return null;
    const identity = `${parsed.data.itemKind}:${parsed.data.itemId.toLowerCase()}`;
    if (seen.has(identity)) return null;
    seen.add(identity);
    items.push(parsed.data);
  }
  return items;
}

export type EmptyTrashResult = {
  deleted: number;
  total: number;
  complete: boolean;
  /** The person left Trash, which stops the batch before its next deletion. */
  left: boolean;
};

// Never fetch more targets while deleting. A failed or uncertain response stops
// the batch and requires a fresh review, rather than a destructive blind retry.
export async function runEmptyTrash(
  snapshot: readonly TrashItemInput[],
  remove: (item: TrashItemInput) => Promise<boolean>,
  progress: (deleted: number) => void,
  shouldContinue: () => boolean = () => true,
): Promise<EmptyTrashResult> {
  let deleted = 0;
  let left = false;
  for (const item of snapshot) {
    if (!shouldContinue()) {
      left = true;
      break;
    }
    try {
      if (!(await remove(item))) break;
    } catch {
      break;
    }
    progress(++deleted);
  }
  return {
    deleted,
    total: snapshot.length,
    complete: deleted === snapshot.length,
    left,
  };
}

export function emptyTrashResultMessage(
  result: EmptyTrashResult,
  filesRemoved = true,
) {
  const stopped = `${result.deleted} of ${countLabel(result.total, "item")} confirmed deleted.`;
  const message = result.complete
    ? `${countLabel(result.deleted, "confirmed item")} permanently deleted. Anything added to Trash later was not included.`
    : result.left
      ? `${stopped} Stopped because you left Trash. Review Trash before trying again.`
      : `${stopped} Stopped because an item changed or a request could not be confirmed. Refresh and review Trash before trying again.`;
  return filesRemoved ? message : `${message} ${PENDING_MEDIA_PURGE_MESSAGE}`;
}
