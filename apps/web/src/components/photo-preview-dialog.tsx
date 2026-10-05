"use client";

import { useEffect } from "react";
import { Button } from "@/components/button";
import { Dialog } from "@/components/dialog";
import { ProgressiveImage } from "@/components/progressive-image";
import styles from "./photo-preview-dialog.module.css";

// Shows one photo. With `position`, it pages through a set with Previous and Next, and
// the arrow keys.
export function PhotoPreviewDialog({
  name,
  onClose,
  onNext,
  onPrevious,
  position,
  src,
}: {
  name: string;
  onClose: () => void;
  onNext?: () => void;
  onPrevious?: () => void;
  position?: { index: number; total: number };
  src: string;
}) {
  const paged = position !== undefined && position.total > 1;
  const hasPrevious = paged && position.index > 0;
  const hasNext = paged && position.index < position.total - 1;

  useEffect(() => {
    if (!paged) return;
    const page = (event: KeyboardEvent) => {
      if (event.key === "ArrowLeft" && hasPrevious) onPrevious?.();
      if (event.key === "ArrowRight" && hasNext) onNext?.();
    };
    document.addEventListener("keydown", page);
    return () => document.removeEventListener("keydown", page);
  }, [hasNext, hasPrevious, onNext, onPrevious, paged]);

  return (
    <Dialog
      open
      closeLabel="Close photo preview"
      eyebrow={<>Photo preview</>}
      footer={
        <>
          {paged ? (
            <div className={styles.navigation}>
              <Button
                disabled={!hasPrevious}
                onClick={onPrevious}
                type="button"
                variant="secondary"
              >
                Previous
              </Button>
              <span aria-live="polite">
                {position.index + 1} of {position.total}
              </span>
              <Button
                disabled={!hasNext}
                onClick={onNext}
                type="button"
                variant="secondary"
              >
                Next
              </Button>
            </div>
          ) : null}
          <Button onClick={onClose} type="button" variant="secondary">
            Close
          </Button>
        </>
      }
      onOpenChange={(open) => {
        if (!open) onClose();
      }}
      size="wide"
      title={name}
    >
      <div className={styles.image}>
        <ProgressiveImage
          alt={name}
          fallback="Photo unavailable. Close this preview and try again."
          fit="contain"
          key={src}
          src={src}
        />
      </div>
    </Dialog>
  );
}
