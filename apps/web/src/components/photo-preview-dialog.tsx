"use client";

import { Button } from "@/components/button";
import { Dialog } from "@/components/dialog";
import { ProgressiveImage } from "@/components/progressive-image";
import styles from "./photo-preview-dialog.module.css";

export function PhotoPreviewDialog({
  name,
  onClose,
  src,
}: {
  name: string;
  onClose: () => void;
  src: string;
}) {
  return (
    <Dialog
      open
      closeLabel="Close photo preview"
      eyebrow={<>Photo preview</>}
      footer={
        <Button onClick={onClose} type="button" variant="secondary">
          Close
        </Button>
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
          src={src}
        />
      </div>
    </Dialog>
  );
}
