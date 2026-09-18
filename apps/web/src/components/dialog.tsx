"use client";

import { Dialog as ArkDialog } from "@ark-ui/react/dialog";
import { Portal } from "@ark-ui/react/portal";
import type { ReactNode, RefObject } from "react";
import { IconButton } from "./button";
import { Icon } from "./icon";
import styles from "./dialog.module.css";

export function Dialog({
  children,
  title,
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
  title: string;
  description?: string;
  footer?: ReactNode;
  trigger?: ReactNode;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  busy?: boolean;
  size?: "compact" | "standard" | "wide";
  closeOnInteractOutside?: boolean;
  portalContainer?: RefObject<HTMLElement | null>;
}) {
  return (
    <ArkDialog.Root
      open={open}
      onOpenChange={({ open: nextOpen }) => {
        if (!busy || nextOpen) onOpenChange(nextOpen);
      }}
      closeOnEscape={!busy}
      closeOnInteractOutside={!busy && closeOnInteractOutside}
      lazyMount
      unmountOnExit
      modal
      trapFocus
      restoreFocus
      preventScroll
    >
      {trigger ? (
        <ArkDialog.Trigger asChild>{trigger}</ArkDialog.Trigger>
      ) : null}
      <Portal container={portalContainer}>
        <ArkDialog.Backdrop className={styles.backdrop} />
        <ArkDialog.Positioner className={styles.positioner}>
          <ArkDialog.Content
            className={styles.dialog}
            data-size={size}
            aria-busy={busy}
          >
            <header className={styles.header}>
              <div>
                <ArkDialog.Title className={styles.title}>
                  {title}
                </ArkDialog.Title>
                {description ? (
                  <ArkDialog.Description className={styles.description}>
                    {description}
                  </ArkDialog.Description>
                ) : null}
              </div>
              <ArkDialog.CloseTrigger asChild>
                <IconButton
                  label={`Close ${title}`}
                  variant="ghost"
                  disabled={busy}
                >
                  <Icon name="close" size={18} />
                </IconButton>
              </ArkDialog.CloseTrigger>
            </header>
            <div className={styles.body}>{children}</div>
            {footer ? (
              <footer className={styles.footer}>{footer}</footer>
            ) : null}
          </ArkDialog.Content>
        </ArkDialog.Positioner>
      </Portal>
    </ArkDialog.Root>
  );
}
