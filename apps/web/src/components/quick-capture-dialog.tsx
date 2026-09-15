"use client";

import { useEffect, useRef } from "react";
import { CaptureComposer } from "@/components/capture-composer";
import { Icon } from "@/components/icon";
import styles from "./quick-capture-dialog.module.css";

export function QuickCaptureDialog({
  idPrefix,
  onClose,
  onOpen,
  open,
  ownerId,
  triggerClassName,
}: {
  idPrefix: string;
  onClose: () => void;
  onOpen: () => void;
  open: boolean;
  ownerId: string;
  triggerClassName: string;
}) {
  const dialogRef = useRef<HTMLDialogElement>(null);

  useEffect(() => {
    const dialog = dialogRef.current;

    if (open && dialog && !dialog.open) {
      dialog.showModal();
    }
  }, [open]);

  useEffect(() => {
    function handleShortcut(event: KeyboardEvent) {
      if (
        event.key.toLocaleLowerCase() !== "j" ||
        (!event.metaKey && !event.ctrlKey) ||
        event.shiftKey ||
        event.altKey ||
        event.repeat
      ) {
        return;
      }

      event.preventDefault();
      onOpen();
    }

    window.addEventListener("keydown", handleShortcut);
    return () => window.removeEventListener("keydown", handleShortcut);
  }, [onOpen]);

  function close() {
    dialogRef.current?.close();
    onClose();
  }

  return (
    <>
      <button
        aria-keyshortcuts="Meta+J Control+J"
        aria-label="New entry"
        aria-haspopup="dialog"
        className={triggerClassName}
        onClick={onOpen}
        type="button"
      >
        <Icon name="plus" size={17} />
        <kbd aria-hidden="true">⌘ J</kbd>
      </button>

      {open ? (
        <dialog
          aria-labelledby={`${idPrefix}-heading`}
          className={styles.dialog}
          onCancel={onClose}
          onClick={(event) => {
            if (event.target === event.currentTarget) {
              close();
            }
          }}
          onClose={onClose}
          ref={dialogRef}
        >
          <header className={styles.dialogHeader}>
            <div className={styles.dialogTitle}>
              <span className={styles.dialogMark} aria-hidden="true">
                <Icon name="sparkle" size={15} />
              </span>
              <h2 id={`${idPrefix}-heading`}>What’s on your mind?</h2>
            </div>
            <button
              aria-label="Close quick capture"
              className={styles.closeButton}
              onClick={close}
              type="button"
            >
              ×
            </button>
          </header>
          <div className={styles.dialogBody}>
            <CaptureComposer
              idPrefix={idPrefix}
              ownerId={ownerId}
              variant="dialog"
            />
          </div>
        </dialog>
      ) : null}
    </>
  );
}
