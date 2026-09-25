"use client";
import { Button } from "@/components/button";
import { useState } from "react";
import { ProgressiveImage } from "@/components/progressive-image";
import type { PhotoPlaceDraft } from "@/lib/media/photo-place";
import { PhotoPlaceEditor } from "./photo-place-draft";
import type {
  EntryPhoto,
  PhotoMetadataResponse,
} from "@/lib/media/photo-metadata";
import styles from "./entry-photo-dates.module.css";

export function EntryPhotoDates({
  entryId,
  disabled,
  onUseDate,
  place,
  onPlaceChange,
}: {
  entryId: string;
  disabled: boolean;
  onUseDate: (date: string) => void;
  place: PhotoPlaceDraft | null;
  onPlaceChange: (value: PhotoPlaceDraft | null) => void;
}) {
  const [photos, setPhotos] = useState<EntryPhoto[] | null>(null);
  const [metadata, setMetadata] = useState<
    Record<string, PhotoMetadataResponse>
  >({});
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  async function load(photo?: EntryPhoto) {
    setBusy(true);
    setError(null);
    setNotice(null);
    try {
      const response = await fetch(
        photo
          ? `/api/media/metadata?attachmentId=${photo.id}`
          : `/api/media/photos?entryId=${entryId}`,
        { method: "POST" },
      );
      if (!response.ok)
        throw Error(
          photo
            ? "Photo metadata is unavailable. The original is unchanged."
            : "Photos could not be loaded. Try again.",
        );
      const data = await response.json();
      if (photo) setMetadata((previous) => ({ ...previous, [photo.id]: data }));
      else {
        setPhotos(data.photos);
        setMetadata({});
        if (data.hasMore) setNotice("Showing the first 100 photos.");
      }
    } catch (error) {
      setError(error instanceof Error ? error.message : "Photos unavailable.");
    } finally {
      setBusy(false);
    }
  }
  return (
    <section className={styles.panel} aria-label="Photo date suggestions">
      <div className={styles.heading}>
        <h3>Photos & camera dates</h3>
        <Button
          variant="secondary"
          type="button"
          disabled={busy || disabled}
          onClick={() => void load()}
        >
          {busy ? "Loading…" : photos ? "Refresh photos" : "Show photos"}
        </Button>
      </div>
      <p>
        Read the original photo&apos;s camera metadata. No AI, no automatic
        changes.
      </p>
      {photos?.length === 0 ? <p>No saved photos on this Entry.</p> : null}
      {photos?.map((photo) => {
        const info = metadata[photo.id];
        return (
          <article className={styles.photo} key={photo.id}>
            {photo.imageUrl ? (
              <ProgressiveImage
                alt={photo.name}
                loading="lazy"
                src={photo.imageUrl}
              />
            ) : null}
            <div>
              <strong>{photo.name}</strong>
              <Button
                variant="secondary"
                type="button"
                disabled={busy || disabled}
                onClick={() => void load(photo)}
              >
                {info ? "Read metadata again" : "Read camera date"}
              </Button>
              {info ? (
                <>
                  <p>
                    {info.capturedLocal
                      ? `Camera time: ${info.capturedLocal.replace("T", " ")}${info.offset ? ` (UTC${info.offset})` : " (time zone not recorded)"}`
                      : "No valid capture date in this photo."}
                  </p>
                  {info.calendarDate ? (
                    <>
                      <Button
                        variant="secondary"
                        type="button"
                        disabled={busy || disabled}
                        onClick={() => {
                          onUseDate(info.calendarDate!);
                          setNotice(
                            "Calendar date added to the draft. Review the date, then save your changes.",
                          );
                        }}
                      >
                        Use calendar date {info.calendarDate}
                      </Button>
                      <p>
                        Uses Day precision and replaces the draft&apos;s date
                        range. It does not infer a time zone or save until you
                        confirm.
                      </p>
                    </>
                  ) : null}
                  {info.latitude !== null && info.longitude !== null ? (
                    <>
                      <p className={styles.coordinates}>
                        Private GPS metadata is available. No Location is linked
                        automatically.
                      </p>
                      <Button
                        variant="secondary"
                        type="button"
                        disabled={
                          disabled ||
                          busy ||
                          (place?.attachmentId === photo.id &&
                            place.kind === "new")
                        }
                        onClick={() =>
                          onPlaceChange({
                            kind: "new",
                            attachmentId: photo.id,
                            name: "Photo GPS location",
                            latitude: info.latitude!,
                            longitude: info.longitude!,
                          })
                        }
                      >
                        Use GPS for a Location
                      </Button>
                    </>
                  ) : null}
                </>
              ) : null}
            </div>
          </article>
        );
      })}
      {error ? <p role="alert">{error}</p> : null}
      {place ? (
        <PhotoPlaceEditor
          key={`${place.attachmentId}:${place.kind}`}
          value={place}
          onChange={onPlaceChange}
          disabled={disabled || busy}
        />
      ) : null}
      {notice ? <p role="status">{notice}</p> : null}
    </section>
  );
}
