"use client";

import type { ReactNode } from "react";
import { Dialog } from "@/components/dialog";
import { PageHeader } from "@/components/page-header";
import styles from "./focused-editor-surface.module.css";

export function FocusedEditorSurface({
  busy = false,
  children,
  closeLabel,
  eyebrow,
  footer,
  onClose,
  presentation = "dialog",
  title,
  titleId,
}: {
  busy?: boolean;
  children: ReactNode;
  closeLabel: string;
  eyebrow: ReactNode;
  footer: ReactNode;
  onClose: () => void;
  presentation?: "dialog" | "page";
  title: ReactNode;
  titleId: string;
}) {
  if (presentation === "page") {
    return (
      <section aria-busy={busy} className={styles.pageEditor}>
        <PageHeader eyebrow={eyebrow} title={title} />
        <div className={styles.body}>{children}</div>
        <footer className={styles.footer}>{footer}</footer>
      </section>
    );
  }

  return (
    <Dialog
      open
      onOpenChange={(open) => {
        if (!open) onClose();
      }}
      title={title}
      titleId={titleId}
      eyebrow={eyebrow}
      closeLabel={closeLabel}
      busy={busy}
      size="wide"
      footer={footer}
    >
      {children}
    </Dialog>
  );
}
