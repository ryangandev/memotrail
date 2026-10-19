"use client";

import { Dialog as ArkDialog } from "@ark-ui/react/dialog";
import { Portal } from "@ark-ui/react/portal";
import { ClientOnly } from "@ark-ui/react/client-only";
import {
  useMemo,
  useRef,
  useState,
  type ReactNode,
  type RefObject,
} from "react";
import { dialogDefaults, type DialogSize } from "@/generated/design-system";
import { OverlayContainerContext } from "./overlay-container";
import { topmostModalDialog, useTopLayerRef } from "./top-layer";
import { IconButton } from "./button";
import { Icon } from "./icon";
import styles from "./dialog.module.css";

/**
 * A modal task over the page, with a title, an optional description, scrolling content, and a
 * footer that stays in reach. Specified in packages/design-system/components/dialog.yaml.
 */
export function Dialog({
  children,
  title,
  titleId,
  eyebrow,
  closeLabel,
  headerContent,
  description,
  footer,
  trigger,
  open,
  onOpenChange,
  busy = dialogDefaults.busy,
  size = dialogDefaults.size,
  closeOnInteractOutside = true,
  portalContainer,
}: {
  children?: ReactNode;
  title: ReactNode;
  titleId?: string;
  eyebrow?: ReactNode;
  closeLabel?: string;
  headerContent?: ReactNode;
  description?: ReactNode;
  footer?: ReactNode;
  trigger?: ReactNode;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  busy?: boolean;
  size?: DialogSize;
  closeOnInteractOutside?: boolean;
  portalContainer?: RefObject<HTMLElement | null>;
}) {
  const container = useRef<HTMLDivElement>(null);
  const host = useModalDialogHost(open && !portalContainer);
  const hostContainer = useMemo(
    () => (host ? { current: host } : undefined),
    [host],
  );
  const topLayerRef = useTopLayerRef<HTMLDivElement>(host !== null);
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
          // A nested layer, such as a calendar, handles its own Escape first.
          const layer =
            event.target instanceof Element
              ? event.target.closest("[data-escape-layer]")
              : null;
          if (layer && layer !== container.current) event.preventDefault();
        }}
        // Mark a control other than the first field with data-autofocus. React's
        // autoFocus focuses it before this dialog traps focus, so an enclosing
        // dialog's trap would take that focus back.
        initialFocusEl={() =>
          container.current?.querySelector<HTMLElement>("[data-autofocus]") ??
          container.current?.querySelector<HTMLElement>(
            "input:not([type=hidden]):not(:disabled), textarea:not(:disabled), [contenteditable=true]",
          ) ??
          null
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
        <Portal container={portalContainer ?? hostContainer}>
          {/* Over a native modal dialog, the positioner draws the scrim as its own
              top-layer backdrop, so nothing can be stacked between the two. */}
          {host ? null : <ArkDialog.Backdrop className={styles.backdrop} />}
          <ArkDialog.Positioner
            className={styles.positioner}
            popover={host ? "manual" : undefined}
            ref={topLayerRef}
          >
            <ArkDialog.Content
              ref={container}
              className={styles.dialog}
              data-escape-layer="dialog"
              data-size={size}
              data-ui-dialog
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
                    variant="quiet"
                    disabled={busy}
                  >
                    <Icon name="close" size={18} />
                  </IconButton>
                </ArkDialog.CloseTrigger>
              </header>
              <OverlayContainerContext value={container}>
                {children ? (
                  <div className={styles.body}>{children}</div>
                ) : null}
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

/**
 * The native modal dialog, such as Quick Capture, that was open when this
 * dialog opened. The dialog renders inside it and above it in the top layer,
 * so it stays interactive. It is read on each opening and kept while the
 * dialog animates closed.
 */
function useModalDialogHost(open: boolean) {
  const [opening, setOpening] = useState<{
    open: boolean;
    host: HTMLDialogElement | null;
  }>({ open: false, host: null });
  if (opening.open === open) return opening.host;
  const host = open ? topmostModalDialog() : opening.host;
  setOpening({ open, host });
  return host;
}
