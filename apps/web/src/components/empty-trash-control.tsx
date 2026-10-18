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

export function EmptyTrashControl({
  disabled,
  onBusy,
  onResult,
  onFinish,
}: {
  disabled: boolean;
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
    if (!alive.current) return;
    deleting.current = false;
    setRunning(false);
    close();
    onResult({
      status: result.complete ? "deleted" : "error",
      message: emptyTrashResultMessage(result, filesRemoved),
    });
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
          title={<>Empty {countLabel(snapshot.length, "item")} from Trash?</>}
          titleId="empty-trash-title"
          description={
            <>
              This includes all Trash pages, not just the visible items. Their
              records and private photos will be permanently removed. This
              cannot be undone.
            </>
          }
          eyebrow={<>Permanent action</>}
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
                {running
                  ? "Emptying Trash…"
                  : "Permanently delete confirmed items"}
              </Button>
            </>
          }
        >
          {" "}
          <p>
            Only this prepared list is included. Items added to Trash later are
            not deleted. If an item changes or a request cannot be confirmed,
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
