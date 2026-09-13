"use client";

import { useEffect, useRef, useState } from "react";
import type { EntryPhoto } from "@/lib/media/photo-metadata";
import styles from "./entry-photo-gallery.module.css";

/** Always current membership, never a historical snapshot's photo bytes. */
export function EntryPhotoGallery({ entryId }: { entryId: string }) {
  const [photos, setPhotos] = useState<EntryPhoto[] | null>(null);
  const [hasMore, setHasMore] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [selected, setSelected] = useState<number | null>(null);
  const [generation, setGeneration] = useState(0);
  const request = useRef<AbortController | null>(null);
  useEffect(() => () => request.current?.abort(), []);

  async function load() {
    request.current?.abort();
    const controller = new AbortController();
    request.current = controller;
    setBusy(true);
    setError(null);
    setPhotos(null);
    setSelected(null);
    setHasMore(false);
    try {
      const response = await fetch(`/api/media/photos?entryId=${entryId}`, {
        method: "POST",
        cache: "no-store",
        signal: AbortSignal.any([
          controller.signal,
          AbortSignal.timeout(30_000),
        ]),
      });
      if (!response.ok) throw Error();
      const data: { photos: EntryPhoto[]; hasMore: boolean } =
        await response.json();
      if (controller.signal.aborted) return;
      setPhotos(data.photos);
      setHasMore(data.hasMore);
      setGeneration((value) => value + 1);
    } catch {
      if (!controller.signal.aborted)
        setError("Could not load photos. Check your connection and try again.");
    } finally {
      if (!controller.signal.aborted) setBusy(false);
    }
  }

  return (
    <section className={styles.panel} aria-label="Current photos">
      <div className={styles.heading}>
        <h3>Current photos</h3>
        <button disabled={busy} onClick={() => void load()}>
          {busy ? "Loading photos…" : photos ? "Refresh photos" : "Show photos"}
        </button>
      </div>
      <p>
        Photos attached now, not the selected earlier version. Refresh to renew
        photo access or check for changes.
      </p>
      {error && <p role="alert">{error}</p>}
      {photos?.length === 0 && (
        <p role="status">No saved photos on this Entry.</p>
      )}
      {hasMore && <p role="status">Showing the first 100 current photos.</p>}
      <div className={styles.grid}>
        {photos?.map((photo, index) => (
          <button
            className={styles.tile}
            key={`${generation}:${photo.id}`}
            aria-label={`Open ${photo.name}`}
            onClick={() => setSelected(index)}
          >
            <PhotoImage photo={photo} />
            <span>{photo.name}</span>
          </button>
        ))}
      </div>
      {photos && selected !== null && (
        <PhotoViewer
          photos={photos}
          initialIndex={selected}
          onClose={() => setSelected(null)}
        />
      )}
    </section>
  );
}

function PhotoImage({ photo }: { photo: EntryPhoto }) {
  const [failed, setFailed] = useState(false);
  const [loaded, setLoaded] = useState(false);
  if (!photo.imageUrl || failed)
    return (
      <span className={styles.unavailable} role="status">
        Photo unavailable. Close the viewer and refresh photos to retry.
      </span>
    );
  return (
    <span className={styles.image}>
      {!loaded && (
        <span className={styles.loading} role="status">
          Loading photo…
        </span>
      )}
      {/* Private, expiring, already optimized media grants cannot use the public Next image cache. */}
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        src={photo.imageUrl}
        alt={photo.name}
        onLoad={() => setLoaded(true)}
        onError={() => setFailed(true)}
      />
    </span>
  );
}

function PhotoViewer({
  photos,
  initialIndex,
  onClose,
}: {
  photos: EntryPhoto[];
  initialIndex: number;
  onClose: () => void;
}) {
  const dialog = useRef<HTMLDialogElement>(null);
  const [index, setIndex] = useState(initialIndex);
  useEffect(() => {
    const element = dialog.current;
    element?.showModal();
    return () => element?.close();
  }, []);
  return (
    <dialog
      ref={dialog}
      className={styles.viewer}
      aria-label="Photo viewer"
      onClose={onClose}
    >
      <div className={styles.heading}>
        <h3>{photos[index].name}</h3>
        <button onClick={onClose}>Close</button>
      </div>
      <div className={styles.fullImage}>
        <PhotoImage key={photos[index].id} photo={photos[index]} />
      </div>
      <div className={styles.navigation}>
        <button
          aria-label="Previous photo"
          disabled={index === 0}
          onClick={() => setIndex(index - 1)}
        >
          Previous
        </button>
        <span aria-live="polite">
          {index + 1} of {photos.length}
        </span>
        <button
          aria-label="Next photo"
          disabled={index === photos.length - 1}
          onClick={() => setIndex(index + 1)}
        >
          Next
        </button>
      </div>
    </dialog>
  );
}
