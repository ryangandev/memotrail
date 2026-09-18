"use client";
import { Button } from "@/components/button";

import { useEffect, useRef, useState } from "react";
import {
  deleteTrashItemForever,
  prepareEmptyTrash,
  type TrashActionResult,
} from "@/app/trash/actions";
import { emptyTrashResultMessage, runEmptyTrash } from "@/lib/data/empty-trash";
import type { TrashItemInput } from "@/lib/data/trash-input";
import styles from "@/app/trash/page.module.css";

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
    const result = await runEmptyTrash(
      snapshot,
      async (item) => (await deleteTrashItemForever(item)).status === "deleted",
      (count) => {
        if (alive.current) setDeleted(count);
      },
      () => alive.current,
    );
    if (!alive.current) return;
    deleting.current = false;
    setRunning(false);
    close();
    onResult({
      status: result.complete ? "deleted" : "error",
      message: emptyTrashResultMessage(result),
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
        <dialog
          className={`${styles.confirmationDialog} ${styles.emptyTrashDialog}`}
          aria-labelledby="empty-trash-title"
          aria-describedby="empty-trash-description"
          ref={(node) => {
            if (node && !node.open) node.showModal();
          }}
          onCancel={(event) => {
            event.preventDefault();
            if (!running) close();
          }}
        >
          <p className={styles.dialogEyebrow}>Permanent action</p>
          <h2 id="empty-trash-title">
            Empty {snapshot.length} items from Trash?
          </h2>
          <p id="empty-trash-description">
            This includes all Trash pages, not just the visible items. Their
            records, associated history and private photos will be permanently
            removed. Removing a Collection only removes its grouping, not active
            Entries. This cannot be undone.
          </p>
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
          <div className={styles.dialogActions}>
            <Button
              variant="secondary"
              autoFocus
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
          </div>
        </dialog>
      )}
    </>
  );
}
