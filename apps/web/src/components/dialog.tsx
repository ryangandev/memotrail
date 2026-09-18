"use client";

import { Dialog as ArkDialog } from "@ark-ui/react/dialog";
import { Portal } from "@ark-ui/react/portal";
import { ClientOnly } from "@ark-ui/react/client-only";
import { useCallback, useRef, type ReactNode, type RefObject } from "react";
import { OverlayContainerContext } from "./overlay-container";
import { IconButton } from "./button";
import { Icon } from "./icon";
import styles from "./dialog.module.css";

export function Dialog({
  children,
  title,
  titleId,
  eyebrow,
  closeLabel,
  contentRef,
  headerContent,
  description,
  footer,
  trigger,
  open,
  onOpenChange,
  busy = false,
  size = "standard",
  closeOnInteractOutside = true,
  portalContainer,
}: {
  children: ReactNode;
  title: ReactNode;
  titleId?: string;
  eyebrow?: ReactNode;
  closeLabel?: string;
  contentRef?: (node: HTMLDivElement | null) => void;
  headerContent?: ReactNode;
  description?: ReactNode;
  footer?: ReactNode;
  trigger?: ReactNode;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  busy?: boolean;
  size?: "compact" | "standard" | "wide";
  closeOnInteractOutside?: boolean;
  portalContainer?: RefObject<HTMLElement | null>;
}) {
  const container = useRef<HTMLDivElement>(null);
  const setContentRef = useCallback(
    (node: HTMLDivElement | null) => {
      container.current = node;
      contentRef?.(node);
    },
    [contentRef],
  );
  return (
    <ClientOnly>
      <ArkDialog.Root
        open={open}
        onOpenChange={({ open: nextOpen }) => {
          if (!busy || nextOpen) onOpenChange(nextOpen);
        }}
        closeOnEscape={!busy}
        onFocusOutside={(event) => event.preventDefault()}
        onEscapeKeyDown={(event) => {
          if (
            event.target instanceof Element &&
            event.target.closest("[data-escape-layer]")
          )
            event.preventDefault();
        }}
        initialFocusEl={() =>
          container.current?.querySelector<HTMLElement>(
            "[autofocus], input:not([type=hidden]):not(:disabled), textarea:not(:disabled), [contenteditable=true]",
          ) ?? null
        }
        closeOnInteractOutside={!busy && closeOnInteractOutside}
        lazyMount
        unmountOnExit
        modal
        trapFocus
        restoreFocus
        preventScroll
        ids={titleId ? { title: titleId } : undefined}
      >
        {trigger ? (
          <ArkDialog.Trigger asChild>{trigger}</ArkDialog.Trigger>
        ) : null}
        <Portal container={portalContainer}>
          <ArkDialog.Backdrop className={styles.backdrop} />
          <ArkDialog.Positioner className={styles.positioner}>
            <ArkDialog.Content
              ref={setContentRef}
              className={styles.dialog}
              data-size={size}
              aria-busy={busy}
            >
              <header className={styles.header}>
                <div>
                  {eyebrow ? <p className={styles.eyebrow}>{eyebrow}</p> : null}
                  <ArkDialog.Title className={styles.title}>
                    {title}
                  </ArkDialog.Title>
                  {description ? (
                    <ArkDialog.Description className={styles.description}>
                      {description}
                    </ArkDialog.Description>
                  ) : null}
                  {headerContent ? (
                    <div className={styles.description}>{headerContent}</div>
                  ) : null}
                </div>
                <ArkDialog.CloseTrigger asChild>
                  <IconButton
                    label={
                      closeLabel ??
                      `Close ${typeof title === "string" ? title : "dialog"}`
                    }
                    variant="ghost"
                    disabled={busy}
                  >
                    <Icon name="close" size={18} />
                  </IconButton>
                </ArkDialog.CloseTrigger>
              </header>
              <OverlayContainerContext value={container}>
                <div className={styles.body}>{children}</div>
              </OverlayContainerContext>
              {footer ? (
                <footer className={styles.footer}>{footer}</footer>
              ) : null}
            </ArkDialog.Content>
          </ArkDialog.Positioner>
        </Portal>
      </ArkDialog.Root>
    </ClientOnly>
  );
}
