"use client";

import { useState } from "react";
import { PhotoPreviewDialog } from "@/components/photo-preview-dialog";
import { ProgressiveImage } from "@/components/progressive-image";
import type { EntryPhoto } from "@/lib/media/photo-metadata";
import styles from "./entry-photos.module.css";

// An Item page's photos. They are added and removed in the editor; here they open in a
// preview that pages through them.
export function EntryPhotos({
  hasMore,
  photos,
}: {
  hasMore: boolean;
  photos: EntryPhoto[];
}) {
  // The preview pages through the photos that can be shown.
  const viewable = photos.filter((item) => item.imageUrl);
  const [selected, setSelected] = useState<number | null>(null);
  const photo = selected === null ? null : viewable[selected];

  return (
    <section aria-label="Photos" className={styles.photos}>
      <div className={styles.grid} data-count={Math.min(photos.length, 3)}>
        {photos.map((item) => (
          <button
            aria-label={`Open ${item.name}`}
            className={styles.tile}
            disabled={!item.imageUrl}
            key={item.id}
            onClick={() =>
              setSelected(viewable.findIndex(({ id }) => id === item.id))
            }
            type="button"
          >
            {item.imageUrl ? (
              <ProgressiveImage
                alt={item.name}
                fallback="Photo unavailable. Refresh the page to load it again."
                loading="lazy"
                src={item.imageUrl}
              />
            ) : (
              <span className={styles.unavailable}>Photo unavailable</span>
            )}
          </button>
        ))}
      </div>
      {hasMore ? (
        <p className={styles.note} role="status">
          Showing the first {photos.length} photos.
        </p>
      ) : null}
      {photo?.imageUrl ? (
        <PhotoPreviewDialog
          name={photo.name}
          onClose={() => setSelected(null)}
          onNext={() => setSelected((index) => (index ?? 0) + 1)}
          onPrevious={() => setSelected((index) => (index ?? 0) - 1)}
          position={{ index: selected!, total: viewable.length }}
          src={photo.imageUrl}
        />
      ) : null}
    </section>
  );
}
