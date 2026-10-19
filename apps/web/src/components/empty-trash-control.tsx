"use client";
import { Dialog } from "@/components/dialog";
import { Button } from "@/components/button";

import { useEffect, useRef, useState } from "react";
import {
  deleteTrashItemForever,
  finishTrashCleanup,
  prepareEmptyTrash,
  type TrashActionResult,
} from "@/app/trash/actions";
import { emptyTrashResultMessage, runEmptyTrash } from "@/lib/data/empty-trash";
import type { TrashItemInput } from "@/lib/data/trash-input";
import { countLabel } from "@/lib/count-label";

/** What a prepared Trash list holds, such as "30 Entries and 1 photo". */
function trashContents(snapshot: TrashItemInput[]) {
  const photos = snapshot.filter((item) => item.itemKind === "attachment");
  const entries = snapshot.length - photos.length;
  return [
    entries > 0 ? countLabel(entries, "Entry") : null,
    photos.length > 0 ? countLabel(photos.length, "photo") : null,
  ]
    .filter(Boolean)
    .join(" and ");
}

export function EmptyTrashControl({
  disabled,
  onBusy,
  onResult,
  onFinish,
  reviewsExist = false,
}: {
  disabled: boolean;
  /** Whether reviews exist, so the confirmation says they are deleted with their Entries. */
  reviewsExist?: boolean;
  onBusy: (busy: boolean) => void;
  onResult: (result: TrashActionResult) => void;
  onFinish: () => void;
}) {
  const [snapshot, setSnapshot] = useState<TrashItemInput[] | null>(null);
  const [preparing, setPreparing] = useState(false);
  const [running, setRunning] = useState(false);
  const [deleted, setDeleted] = useState(0);
  const alive = useRef(true);
  const locked = useRef(false);
  const deleting = useRef(false);
  useEffect(() => {
    alive.current = true;
    return () => {
      alive.current = false;
    };
  }, []);
  useEffect(() => {
    if (!running) return;
    const warn = (event: BeforeUnloadEvent) => {
      event.preventDefault();
      event.returnValue = "";
    };
    window.addEventListener("beforeunload", warn);
    return () => window.removeEventListener("beforeunload", warn);
  }, [running]);

  function close() {
    setSnapshot(null);
    locked.current = false;
    onBusy(false);
  }
  async function prepare() {
    if (locked.current) return;
    locked.current = true;
    setPreparing(true);
    onBusy(true);
    try {
      const result = await prepareEmptyTrash();
      if (!alive.current) return;
      if (result.error || !result.items?.length) {
        onResult({
          status: result.error ? "error" : "restored",
          message: result.error ?? "Nothing in Trash. No items were deleted.",
        });
        close();
        onFinish();
      } else {
        setDeleted(0);
        setSnapshot(result.items);
      }
    } catch {
      if (alive.current) {
        onResult({
          status: "error",
          message: "Could not prepare Trash. Nothing was deleted.",
        });
        close();
      }
    } finally {
      if (alive.current) setPreparing(false);
    }
  }
  async function confirm() {
    if (!snapshot || deleting.current) return;
    deleting.current = true;
    setRunning(true);
    // Records are deleted one at a time; their private photo files go once at the end.
    const result = await runEmptyTrash(
      snapshot,
      async (item) =>
        (await deleteTrashItemForever(item, { finishCleanup: false }))
          .status === "deleted",
      (count) => {
        if (alive.current) setDeleted(count);
      },
      () => alive.current,
    );
    const filesRemoved =
      result.deleted === 0 || (await finishTrashCleanup().catch(() => false));
    deleting.current = false;
    // The outcome is reported even when this control is gone: the last
    // deletion can refresh Trash to empty, which removes it before this point.
    onResult({
      status: result.complete ? "deleted" : "error",
      message: emptyTrashResultMessage(result, filesRemoved),
    });
    if (!alive.current) {
      onBusy(false);
      return;
    }
    setRunning(false);
    close();
    onFinish();
  }
  return (
    <>
      <Button
        variant="danger"
        disabled={disabled || preparing || running || snapshot !== null}
        onClick={prepare}
        type="button"
      >
        {preparing ? "Preparing Trash…" : "Empty Trash"}
      </Button>
      {snapshot && (
        <Dialog
          open
          size="compact"
          title={<>Delete {trashContents(snapshot)} forever?</>}
          titleId="empty-trash-title"
          description={
            <>
              This includes every page of Trash, not just the visible rows.
              {reviewsExist
                ? " Reviews that read these Entries are deleted too."
                : ""}{" "}
              This cannot be undone.
            </>
          }
          busy={running}
          onOpenChange={(open) => {
            if (!open) close();
          }}
          closeOnInteractOutside={false}
          footer={
            <>
              <Button
                variant="secondary"
                data-autofocus
                disabled={running}
                onClick={close}
                type="button"
              >
                Cancel
              </Button>
              <Button
                variant="danger"
                disabled={running}
                onClick={confirm}
                type="button"
              >
                {running ? "Emptying Trash…" : "Delete forever"}
              </Button>
            </>
          }
        >
          {" "}
          <p>
            Only this prepared list is included. Anything added to Trash later
            is not deleted. If an item changes or a request cannot be confirmed,
            deletion stops for a fresh review.
          </p>
          {running && (
            <p role="status">
              {deleted} of {snapshot.length} confirmed deleted. Keep this page
              open.
            </p>
          )}
        </Dialog>
      )}
    </>
  );
}
