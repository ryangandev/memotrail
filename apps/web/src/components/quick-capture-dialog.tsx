"use client";

import { useCallback, useEffect, useLayoutEffect, useRef } from "react";
import {
  CaptureComposer,
  type NativePhotoPickerState,
} from "@/components/capture-composer";
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
  const nativePhotoPickerOpenRef = useRef(false);
  const suppressEscapeUntilRef = useRef(0);
  const close = useCallback(() => {
    nativePhotoPickerOpenRef.current = false;
    suppressEscapeUntilRef.current = 0;
    dialogRef.current?.close();
    onClose();
  }, [onClose]);
  const handleNativePhotoPickerChange = useCallback(
    (state: NativePhotoPickerState) => {
      if (state === "opened") {
        nativePhotoPickerOpenRef.current = true;
        suppressEscapeUntilRef.current = 0;
        return;
      }

      const wasOpen = nativePhotoPickerOpenRef.current;
      nativePhotoPickerOpenRef.current = false;

      if (state === "selected") {
        suppressEscapeUntilRef.current = 0;
      } else if (wasOpen) {
        suppressEscapeUntilRef.current = performance.now() + 250;
      }
    },
    [],
  );

  useLayoutEffect(() => {
    const dialog = dialogRef.current;

    if (open && dialog && !dialog.open) {
      dialog.showModal();
    }
  }, [open]);

  useEffect(() => {
    function handleShortcut(event: KeyboardEvent) {
      if (
        event.defaultPrevented ||
        event.key.toLocaleLowerCase() !== "j" ||
        (!event.metaKey && !event.ctrlKey) ||
        event.shiftKey ||
        event.altKey ||
        event.repeat ||
        isEditableTarget(event.target)
      ) {
        return;
      }

      event.preventDefault();
      onOpen();
    }

    window.addEventListener("keydown", handleShortcut);
    return () => window.removeEventListener("keydown", handleShortcut);
  }, [onOpen]);

  useEffect(() => {
    if (!open) return;

    function closeOnEscape(event: KeyboardEvent) {
      if (event.key !== "Escape") return;

      if (
        event.target instanceof Element &&
        event.target.closest("[data-escape-layer]")
      ) {
        nativePhotoPickerOpenRef.current = false;
        suppressEscapeUntilRef.current = 0;
        return;
      }

      if (
        nativePhotoPickerOpenRef.current ||
        performance.now() < suppressEscapeUntilRef.current
      ) {
        nativePhotoPickerOpenRef.current = false;
        suppressEscapeUntilRef.current = 0;
        event.preventDefault();
        event.stopPropagation();
        return;
      }

      event.preventDefault();
      event.stopPropagation();
      close();
    }

    function handleWindowFocus() {
      if (!nativePhotoPickerOpenRef.current) return;
      nativePhotoPickerOpenRef.current = false;
      suppressEscapeUntilRef.current = performance.now() + 250;
    }

    window.addEventListener("keydown", closeOnEscape);
    window.addEventListener("focus", handleWindowFocus);
    return () => {
      window.removeEventListener("keydown", closeOnEscape);
      window.removeEventListener("focus", handleWindowFocus);
    };
  }, [close, open]);

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
        <span>New</span>
        <kbd aria-hidden="true">⌘ J</kbd>
      </button>

      {open ? (
        <dialog
          aria-labelledby={`${idPrefix}-heading`}
          className={styles.dialog}
          onCancel={(event) => {
            if (event.target !== event.currentTarget) return;
            event.preventDefault();
            close();
          }}
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
              onNativePhotoPickerChange={handleNativePhotoPickerChange}
              ownerId={ownerId}
              variant="dialog"
            />
          </div>
        </dialog>
      ) : null}
    </>
  );
}

function isEditableTarget(target: EventTarget | null) {
  return (
    target instanceof HTMLElement &&
    (target.isContentEditable || Boolean(target.closest("input, textarea")))
  );
}
