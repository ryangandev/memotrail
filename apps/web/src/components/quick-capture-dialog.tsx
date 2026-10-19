"use client";

import { usePathname } from "next/navigation";
import { useCallback, useEffect, useLayoutEffect, useRef } from "react";
import {
  CaptureComposer,
  type NativePhotoPickerState,
} from "@/components/capture-composer";
import { Icon } from "@/components/icon";
import { IconButton } from "@/components/button";
import { OverlayContainerContext } from "./overlay-container";
import styles from "./quick-capture-dialog.module.css";
import dockStyles from "./workspace-action-dock.module.css";

export function QuickCaptureDialog({
  idPrefix,
  onClose,
  onOpen,
  open,
}: {
  idPrefix: string;
  onClose: () => void;
  onOpen: () => void;
  open: boolean;
}) {
  // The Dashboard has its own composer, so its dock offers Search alone. Quick Capture still
  // opens there with Command J and from the Command Palette.
  const showTrigger = usePathname() !== "/";
  const dialogRef = useRef<HTMLDialogElement>(null);
  const triggerRef = useRef<HTMLButtonElement>(null);
  const nativePhotoPickerOpenRef = useRef(false);
  const suppressEscapeUntilRef = useRef(0);
  const close = useCallback(() => {
    nativePhotoPickerOpenRef.current = false;
    suppressEscapeUntilRef.current = 0;
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
    if (!dialog) return;

    if (open) {
      if (!dialog.open) dialog.showModal();
      return;
    }
    if (!dialog.open) return;

    let canceled = false;
    const finishClosing = () => {
      if (canceled) return;
      dialog.close();
      // Without a trigger, the browser returns focus to where it was before the dialog opened.
      triggerRef.current?.focus({ preventScroll: true });
    };
    const animations = dialog.getAnimations();
    if (animations.length === 0) {
      finishClosing();
    } else {
      void Promise.allSettled(
        animations.map((animation) => animation.finished),
      ).then(finishClosing);
    }
    return () => {
      canceled = true;
    };
  }, [open]);

  useEffect(() => {
    if (!open || !window.visualViewport) return;
    const viewport = window.visualViewport;
    function updateViewport() {
      const dialog = dialogRef.current;
      if (!dialog) return;
      dialog.style.setProperty(
        "--capture-viewport-height",
        `${viewport.height}px`,
      );
      dialog.style.setProperty(
        "--capture-keyboard-offset",
        `${Math.max(0, window.innerHeight - viewport.height - viewport.offsetTop)}px`,
      );
    }
    updateViewport();
    viewport.addEventListener("resize", updateViewport);
    viewport.addEventListener("scroll", updateViewport);
    return () => {
      viewport.removeEventListener("resize", updateViewport);
      viewport.removeEventListener("scroll", updateViewport);
    };
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
        event.isComposing ||
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
      // Escape in the writing field collapses the composer; nested controls
      // retain their own dismissal behavior.
      if (
        event.defaultPrevented &&
        !(event.target instanceof HTMLElement && event.target.isContentEditable)
      )
        return;

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
      {showTrigger ? (
        <button
          aria-keyshortcuts="Meta+J Control+J"
          aria-label="New entry"
          aria-haspopup="dialog"
          aria-expanded={open}
          aria-controls={open ? `${idPrefix}-dialog` : undefined}
          className={`${dockStyles.control} ${styles.trigger}`}
          onClick={onOpen}
          ref={triggerRef}
          title="New entry (⌘ J / Ctrl+J)"
          type="button"
        >
          <Icon name="sparkle" size={18} />
          <span className={styles.triggerPrompt}>What’s on your mind?</span>
          <kbd aria-hidden="true">⌘ J</kbd>
        </button>
      ) : null}

      <dialog
        aria-labelledby={`${idPrefix}-heading`}
        className={styles.dialog}
        data-state={open ? "open" : "closing"}
        id={`${idPrefix}-dialog`}
        onKeyDown={(event) => {
          if (event.key !== "Tab" || event.defaultPrevented) return;
          if (
            !(event.target instanceof Element) ||
            event.target.closest("dialog, [data-escape-layer]") !==
              event.currentTarget
          )
            return;
          const controls = Array.from(
            event.currentTarget.querySelectorAll<HTMLElement>(
              'a[href], button, input, select, textarea, [tabindex], [contenteditable="true"]',
            ),
          ).filter(
            (element) =>
              element.tabIndex >= 0 &&
              !element.matches(":disabled") &&
              element.getClientRects().length > 0,
          );
          const first = controls[0];
          const last = controls.at(-1);
          if (event.shiftKey && document.activeElement === first) {
            event.preventDefault();
            last?.focus();
          } else if (!event.shiftKey && document.activeElement === last) {
            event.preventDefault();
            first?.focus();
          }
        }}
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
        onClose={(event) => {
          if (event.target === event.currentTarget && !event.currentTarget.open)
            onClose();
        }}
        ref={dialogRef}
      >
        <header className={styles.dialogHeader}>
          <h2 id={`${idPrefix}-heading`}>What’s on your mind?</h2>
          <IconButton
            label="Close quick capture"
            size="small"
            variant="quiet"
            onClick={close}
            title="Collapse composer (Esc)"
            type="button"
          >
            <Icon name="close" size={18} />
          </IconButton>
        </header>
        <div className={styles.dialogBody}>
          <OverlayContainerContext value={dialogRef}>
            <CaptureComposer
              active={open}
              idPrefix={idPrefix}
              onNativePhotoPickerChange={handleNativePhotoPickerChange}
              variant="dialog"
            />
          </OverlayContainerContext>
        </div>
      </dialog>
    </>
  );
}

function isEditableTarget(target: EventTarget | null) {
  return (
    target instanceof HTMLElement &&
    (target.isContentEditable || Boolean(target.closest("input, textarea")))
  );
}
