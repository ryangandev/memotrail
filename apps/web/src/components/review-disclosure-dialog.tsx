"use client";

import { Button } from "@/components/button";
import { Dialog } from "@/components/dialog";
import styles from "@/components/review-disclosure-dialog.module.css";
import {
  REVIEW_DISCLOSURE_INTRO,
  REVIEW_DISCLOSURE_SECTIONS,
  REVIEW_DISCLOSURE_SOURCES,
  REVIEW_DISCLOSURE_TITLE,
} from "@/lib/ai/review-disclosure";

/**
 * What a person agrees to before Claude reads their writing: what is sent, what Anthropic does
 * with it, and what MemoTrail keeps. `confirmLabel` is the action that turns reviews on;
 * without it the dialog is read-only and only closes.
 */
export function ReviewDisclosureDialog({
  busy = false,
  confirmLabel,
  onClose,
  onConfirm,
  open,
}: {
  busy?: boolean;
  confirmLabel?: string;
  onClose: () => void;
  onConfirm?: () => void;
  open: boolean;
}) {
  return (
    <Dialog
      busy={busy}
      closeLabel="Close"
      eyebrow="Your privacy"
      footer={
        confirmLabel && onConfirm ? (
          <>
            <Button disabled={busy} onClick={onClose} variant="secondary">
              Not now
            </Button>
            <Button
              data-autofocus
              loading={busy}
              onClick={onConfirm}
              variant="primary"
            >
              {confirmLabel}
            </Button>
          </>
        ) : (
          <Button data-autofocus onClick={onClose} variant="primary">
            Close
          </Button>
        )
      }
      onOpenChange={(next) => {
        if (!next) onClose();
      }}
      open={open}
      title={REVIEW_DISCLOSURE_TITLE}
    >
      <div className={styles.copy}>
        <div className={styles.intro}>
          {REVIEW_DISCLOSURE_INTRO.map((line) => (
            <p key={line}>{line}</p>
          ))}
        </div>
        {REVIEW_DISCLOSURE_SECTIONS.map((section) => (
          <section key={section.heading}>
            <h3>{section.heading}</h3>
            <ul>
              {section.points.map((point) => (
                <li key={point}>{point}</li>
              ))}
            </ul>
          </section>
        ))}
        <p className={styles.sources}>
          Sources: Anthropic Privacy Center,{" "}
          <a
            href={REVIEW_DISCLOSURE_SOURCES[0].href}
            rel="noopener noreferrer"
            target="_blank"
          >
            {REVIEW_DISCLOSURE_SOURCES[0].label}
          </a>{" "}
          and{" "}
          <a
            href={REVIEW_DISCLOSURE_SOURCES[1].href}
            rel="noopener noreferrer"
            target="_blank"
          >
            {REVIEW_DISCLOSURE_SOURCES[1].label}
          </a>
          , and Anthropic&apos;s{" "}
          <a
            href={REVIEW_DISCLOSURE_SOURCES[2].href}
            rel="noopener noreferrer"
            target="_blank"
          >
            {REVIEW_DISCLOSURE_SOURCES[2].label}
          </a>
          , checked October 18, 2026.
        </p>
      </div>
    </Dialog>
  );
}
