"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import type { EntryPhoto } from "@/lib/media/photo-metadata";
import { uploadEntryPhotos } from "@/lib/media/upload";
import {
  validateInboxPhotoFiles,
  inboxPhotoLimit,
} from "@/lib/data/inbox-photo";
import { registerEntryAttachment } from "@/app/inbox/actions";
import { trashEntryPhoto } from "@/app/history/media-actions";
import { ProgressiveImage } from "@/components/progressive-image";
import styles from "./entry-photo-gallery.module.css";

/** Always current membership, never a historical snapshot's photo bytes. */
export function EntryPhotoGallery({
  entryId,
  entryRevision,
  ownerId,
  onChanged,
}: {
  entryId: string;
  entryRevision: number;
  ownerId: string;
  onChanged: () => void;
}) {
  const [photos, setPhotos] = useState<EntryPhoto[] | null>(null);
  const [hasMore, setHasMore] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [selected, setSelected] = useState<number | null>(null);
  const [generation, setGeneration] = useState(0);
  const [pending, setPending] = useState<File[]>([]);
  const [notice, setNotice] = useState<string | null>(null);
  const request = useRef<AbortController | null>(null);
  const observedRevision = useRef(entryRevision);
  useEffect(() => () => request.current?.abort(), []);

  const load = useCallback(async () => {
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
  }, [entryId]);

  useEffect(() => {
    if (
      observedRevision.current === entryRevision ||
      busy ||
      pending.length > 0
    )
      return;
    // Refresh current membership after writing/history changes, but retain an
    // unconfirmed selection and its upload identity across Server Action refreshes.
    // Coalesce server refreshes after commit; cancel if a user operation begins.
    const refresh = window.setTimeout(() => {
      observedRevision.current = entryRevision;
      if (photos !== null) void load();
    }, 0);
    return () => window.clearTimeout(refresh);
  }, [entryRevision, busy, pending.length, photos, load]);

  async function upload() {
    if (busy || pending.length === 0) return;
    setBusy(true);
    setError(null);
    setNotice(null);
    try {
      const failed = await uploadEntryPhotos(
        ownerId,
        entryId,
        pending,
        async (input) => {
          const result = await registerEntryAttachment(input);
          return { status: result.status === "synced" ? "saved" : "error" };
        },
      );
      setPending(failed);
      await load();
      if (failed.length)
        setError(
          "Some photos are not confirmed. Keep this view open and select Upload photos again to retry safely.",
        );
      else {
        setNotice("Photos attached.");
        onChanged();
      }
    } catch {
      setError(
        "Could not confirm photo uploads. Keep this view open and retry.",
      );
    } finally {
      setBusy(false);
    }
  }

  async function remove(photo: EntryPhoto) {
    if (
      busy ||
      !confirm(`Move ${photo.name} to Trash? The original will be preserved.`)
    )
      return;
    setBusy(true);
    setError(null);
    setNotice(null);
    try {
      const confirmed = await trashEntryPhoto(entryId, photo.id);
      await load();
      if (!confirmed)
        setError(
          "Could not confirm removal. Refresh to check the current photos before retrying.",
        );
      else {
        setNotice("Photo moved to Trash. Restore it from Trash any time.");
        onChanged();
      }
    } catch {
      setError(
        "Could not confirm removal. Refresh to check the current photos before retrying.",
      );
    } finally {
      setBusy(false);
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
      {notice && <p role="status">{notice}</p>}
      {photos && (
        <label className={styles.picker}>
          Add photos
          <input
            type="file"
            multiple
            accept="image/jpeg,image/png,image/webp,image/heic,image/heif,.heic,.heif"
            disabled={
              busy ||
              hasMore ||
              pending.length > 0 ||
              photos.length >= inboxPhotoLimit
            }
            onChange={(event) => {
              const selection = validateInboxPhotoFiles(
                Array.from(event.target.files ?? []),
                photos.length,
              );
              setPending(selection.accepted.map((draft) => draft.file));
              setError(selection.message);
              setNotice(null);
              event.target.value = "";
            }}
          />
        </label>
      )}
      <p>
        Up to {inboxPhotoLimit} photos, 50 MB each. Selected photos stay in this
        view until you upload or leave.
      </p>
      {pending.length > 0 && (
        <div className={styles.pending}>
          <h4>Selected photos</h4>
          {pending.map((file, index) => (
            <div key={index} className={styles.pendingRow}>
              <span>{file.name}</span>
              <button
                disabled={busy}
                aria-label={`Discard selected ${file.name}`}
                onClick={() =>
                  setPending(pending.filter((_, i) => i !== index))
                }
              >
                Discard selection
              </button>
            </div>
          ))}
          <button disabled={busy} onClick={() => void upload()}>
            {busy ? "Saving photos…" : "Upload photos"}
          </button>
        </div>
      )}
      {photos?.length === 0 && (
        <p role="status">No saved photos on this Entry.</p>
      )}
      {hasMore && <p role="status">Showing the first 100 current photos.</p>}
      <div className={styles.grid}>
        {photos?.map((photo, index) => (
          <div className={styles.photoCard} key={`${generation}:${photo.id}`}>
            <button
              className={styles.tile}
              aria-label={`Open ${photo.name}`}
              onClick={() => setSelected(index)}
            >
              <PhotoImage photo={photo} />
              <span>{photo.name}</span>
            </button>
            <button
              disabled={busy || pending.length > 0}
              aria-label={`Move ${photo.name} to Trash`}
              onClick={() => void remove(photo)}
            >
              Move to Trash
            </button>
          </div>
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
  if (!photo.imageUrl)
    return (
      <span className={styles.unavailable} role="status">
        Photo unavailable. Close the viewer and refresh photos to retry.
      </span>
    );
  return (
    <ProgressiveImage
      alt={photo.name}
      className={styles.image}
      fallback="Photo unavailable. Close the viewer and refresh photos to retry."
      fit="contain"
      src={photo.imageUrl}
    />
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

    if (element && !element.open) {
      element.showModal();
    }
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
