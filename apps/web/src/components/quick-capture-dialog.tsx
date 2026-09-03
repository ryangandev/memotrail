"use client";

import { useEffect, useRef, useState } from "react";
import { CaptureComposer } from "@/components/capture-composer";
import { Icon } from "@/components/icon";
import styles from "./quick-capture-dialog.module.css";

export function QuickCaptureDialog({
  compact = false,
  idPrefix,
  ownerId,
}: {
  compact?: boolean;
  idPrefix: string;
  ownerId: string;
}) {
  const dialogRef = useRef<HTMLDialogElement>(null);
  const [isOpen, setIsOpen] = useState(false);

  useEffect(() => {
    const dialog = dialogRef.current;

    if (isOpen && dialog && !dialog.open) {
      dialog.showModal();
    }
  }, [isOpen]);

  function close() {
    dialogRef.current?.close();
    setIsOpen(false);
  }

  return (
    <>
      <button
        aria-haspopup="dialog"
        className={`${styles.trigger} ${compact ? styles.compactTrigger : ""}`}
        onClick={() => setIsOpen(true)}
        type="button"
      >
        <Icon name="plus" size={17} />
        <span>New entry</span>
      </button>

      {isOpen ? (
        <dialog
          aria-labelledby={`${idPrefix}-heading`}
          className={styles.dialog}
          onCancel={() => setIsOpen(false)}
          onClick={(event) => {
            if (event.target === event.currentTarget) {
              close();
            }
          }}
          onClose={() => setIsOpen(false)}
          ref={dialogRef}
        >
          <header className={styles.dialogHeader}>
            <div>
              <p>Quick capture</p>
              <h2 id={`${idPrefix}-heading`}>Keep what is on your mind</h2>
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
