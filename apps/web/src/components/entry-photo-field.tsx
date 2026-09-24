"use client";

import { useState } from "react";
import { Icon } from "@/components/icon";
import { PhotoPreviewDialog } from "@/components/photo-preview-dialog";
import { PhotoUploadProgress } from "@/components/photo-upload-progress";
import { ProgressiveImage } from "@/components/progressive-image";
import { SelectedPhotoPreview } from "@/components/selected-photo-preview";
import type { PhotoUploadProgress as PhotoUploadProgressValue } from "@/lib/media/upload";
import styles from "./entry-photo-field.module.css";

type ExistingPhoto = {
  id: string;
  imageUrl: string | null;
  originalFilename: string | null;
};

export function EntryPhotoField<Photo extends ExistingPhoto>({
  disabled,
  existingPhotos,
  limit,
  onRemoveExisting,
  onRemovePending,
  onSelect,
  pendingPhotos,
  progress,
  recordLabel,
}: {
  disabled: boolean;
  existingPhotos: Photo[];
  limit: number;
  onRemoveExisting: (photo: Photo) => void;
  onRemovePending: (index: number) => void;
  onSelect: (files: File[]) => void;
  pendingPhotos: File[];
  progress: PhotoUploadProgressValue | null;
  recordLabel: string;
}) {
  const full = existingPhotos.length + pendingPhotos.length >= limit;
  const [previewPhotoId, setPreviewPhotoId] = useState<string | null>(null);
  const previewPhoto = existingPhotos.find(
    (photo) => photo.id === previewPhotoId,
  );

  return (
    <fieldset
      className={styles.field}
      data-entry-photo-field="true"
      data-ui-field
    >
      <legend>Photos</legend>
      {existingPhotos.length > 0 || pendingPhotos.length > 0 ? (
        <div className={styles.grid}>
          {existingPhotos.map((photo) => (
            <div className={styles.tile} key={photo.id}>
              {photo.imageUrl ? (
                <button
                  aria-label={`Preview ${photo.originalFilename ?? `${recordLabel} photo`}`}
                  className={styles.previewTrigger}
                  onClick={() => setPreviewPhotoId(photo.id)}
                  type="button"
                >
                  <ProgressiveImage
                    alt={photo.originalFilename ?? `${recordLabel} photo`}
                    src={photo.imageUrl}
                  />
                </button>
              ) : (
                <span className={styles.fallback}>Private photo</span>
              )}
              <button
                aria-label={`Remove ${photo.originalFilename ?? "photo"}`}
                className={styles.removeButton}
                disabled={disabled}
                onClick={() => onRemoveExisting(photo)}
                type="button"
              >
                <Icon name="close" size={16} />
              </button>
            </div>
          ))}
          {pendingPhotos.map((file, index) => (
            <div
              className={styles.tile}
              key={`${file.name}:${file.size}:${file.lastModified}:${index}`}
            >
              <SelectedPhotoPreview alt={`Selected ${file.name}`} file={file} />
              <span className={styles.pendingBadge}>New</span>
              {index === 0 &&
              progress &&
              progress.total > 0 &&
              progress.completed < progress.total ? (
                <PhotoUploadProgress progress={progress} variant="overlay" />
              ) : null}
              <button
                aria-label={`Remove selected ${file.name}`}
                className={styles.removeButton}
                disabled={disabled}
                onClick={() => onRemovePending(index)}
                type="button"
              >
                <Icon name="close" size={16} />
              </button>
            </div>
          ))}
        </div>
      ) : null}
      {previewPhoto?.imageUrl ? (
        <PhotoPreviewDialog
          name={previewPhoto.originalFilename ?? `${recordLabel} photo`}
          onClose={() => setPreviewPhotoId(null)}
          src={previewPhoto.imageUrl}
        />
      ) : null}
      <label className={styles.picker}>
        <Icon name="photo" size={18} />
        <span>Add photos</span>
        <input
          accept="image/jpeg,image/png,image/webp,image/heic,image/heif,.heic,.heif"
          disabled={disabled || full}
          multiple
          onChange={(event) => {
            const files = Array.from(event.target.files ?? []);
            event.target.value = "";
            if (files.length > 0) onSelect(files);
          }}
          type="file"
        />
      </label>
      <small>Originals stay private. Up to {limit} photos, 50 MB each.</small>
    </fieldset>
  );
}
