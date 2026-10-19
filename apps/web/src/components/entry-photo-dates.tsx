"use client";
import { Button } from "@/components/button";
import { useState } from "react";
import { ProgressiveImage } from "@/components/progressive-image";
import type { PhotoLocationDraft } from "@/lib/media/photo-location";
import { PhotoLocationEditor } from "./photo-location-draft";
import type {
  EntryPhoto,
  PhotoMetadataResponse,
} from "@/lib/media/photo-metadata";
import styles from "./entry-photo-dates.module.css";

// Reads a saved photo's camera date or GPS position on request. Nothing changes until
// the editor is saved.
export function EntryPhotoDates({
  disabled,
  onUseDate,
  photoLocation,
  onPhotoLocationChange,
  photos,
}: {
  disabled: boolean;
  onUseDate: (date: string) => void;
  photoLocation: PhotoLocationDraft | null;
  onPhotoLocationChange: (value: PhotoLocationDraft | null) => void;
  photos: EntryPhoto[];
}) {
  const [metadata, setMetadata] = useState<
    Record<string, PhotoMetadataResponse>
  >({});
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  async function load(photo: EntryPhoto) {
    setBusy(true);
    setError(null);
    setNotice(null);
    try {
      const response = await fetch(
        `/api/media/metadata?attachmentId=${photo.id}`,
        { method: "POST" },
      );
      if (!response.ok)
        throw Error(
          "Photo metadata is unavailable. The original is unchanged.",
        );
      const data = await response.json();
      setMetadata((previous) => ({ ...previous, [photo.id]: data }));
    } catch (error) {
      setError(error instanceof Error ? error.message : "Photos unavailable.");
    } finally {
      setBusy(false);
    }
  }
  return (
    <section className={styles.panel} aria-label="Photo date suggestions">
      <h3>Camera dates</h3>
      <p>
        Read a saved photo&apos;s camera date or GPS position. No AI, no
        automatic changes.
      </p>
      <ul className={styles.photos}>
        {photos.map((photo) => {
          const info = metadata[photo.id];
          return (
            <li className={styles.photo} key={photo.id}>
              {photo.imageUrl ? (
                <ProgressiveImage
                  alt={photo.name}
                  className={styles.thumbnail}
                  loading="lazy"
                  src={photo.imageUrl}
                />
              ) : null}
              <div>
                <strong>{photo.name}</strong>
                <Button
                  variant="secondary"
                  size="small"
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
                          Private GPS metadata is available. No Location is
                          linked automatically.
                        </p>
                        <Button
                          variant="secondary"
                          type="button"
                          disabled={
                            disabled ||
                            busy ||
                            photoLocation?.attachmentId === photo.id
                          }
                          onClick={() =>
                            onPhotoLocationChange({
                              attachmentId: photo.id,
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
            </li>
          );
        })}
      </ul>
      {error ? <p role="alert">{error}</p> : null}
      {photoLocation ? (
        <PhotoLocationEditor
          key={photoLocation.attachmentId}
          value={photoLocation}
          onChange={onPhotoLocationChange}
          disabled={disabled || busy}
        />
      ) : null}
      {notice ? <p role="status">{notice}</p> : null}
    </section>
  );
}
