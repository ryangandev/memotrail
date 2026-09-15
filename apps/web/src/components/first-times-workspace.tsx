"use client";

import {
  useEffect,
  useRef,
  useState,
  type ChangeEvent,
  type FormEvent,
} from "react";
import { useRouter } from "next/navigation";
import {
  registerFirstTimeAttachment,
  saveFirstTimeEntry,
  trashFirstTimeAttachment,
  trashFirstTimeEntry,
  type FirstTimeActionResult,
} from "@/app/first-times/actions";
import styles from "@/app/first-times/page.module.css";
import { EntryOrganizationEditor } from "@/components/entry-organization-editor";
import { Icon } from "@/components/icon";
import { PageFrame } from "@/components/page-frame";
import { ProgressiveImage } from "@/components/progressive-image";
import {
  firstTimeBodyLimit,
  firstTimePhotoLimit,
  firstTimePhotoSizeLimit,
  firstTimeTitleLimit,
  inferFirstTimeImageMimeType,
  parseFirstTimeEntryInput,
  type FirstTimeEntryInput,
} from "@/lib/data/first-time-input";
import type {
  FirstTimeAttachment,
  FirstTimeEntry,
} from "@/lib/data/first-times";
import { OccurrenceEditor } from "@/components/occurrence-editor";
import {
  occurrenceDraft,
  occurrenceLabel,
  resolveOccurrenceDraft,
  type Occurrence,
} from "@/lib/data/occurrence";
import { uploadEntryPhotos } from "@/lib/media/upload";

export function FirstTimesWorkspace({
  collectionOptions,
  entries,
  loadError,
  ownerId,
  tagOptions,
}: {
  collectionOptions: string[];
  entries: FirstTimeEntry[];
  loadError: string | null;
  ownerId: string;
  tagOptions: string[];
}) {
  const [selectedEntry, setSelectedEntry] = useState<FirstTimeEntry | null>();
  const [confirmedEntries, setConfirmedEntries] = useState<
    Record<string, FirstTimeEntry>
  >({});
  const visibleEntries = entries.map((entry) => {
    const confirmed = confirmedEntries[entry.id];
    return confirmed && confirmed.revision > entry.revision ? confirmed : entry;
  });
  const photoCount = entries.reduce(
    (count, entry) => count + originalAttachments(entry).length,
    0,
  );

  return (
    <PageFrame variant="wide">
      <header className={styles.pageHeader}>
        <div>
          <p className={styles.eyebrow}>A record of beginnings</p>
          <h1>First Times</h1>
          <p>
            Keep the small beginnings and major milestones worth finding again.
          </p>
        </div>
        <button
          aria-label="Add First Time"
          className={styles.addButton}
          onClick={() => setSelectedEntry(null)}
          type="button"
        >
          <Icon name="plus" />
          <span>Add First Time</span>
        </button>
      </header>

      <div className={styles.summary} aria-label="First Times summary">
        <span>{countLabel(entries.length, "First Time")}</span>
        <span aria-hidden="true">·</span>
        <span>{countLabel(photoCount, "photo")}</span>
      </div>

      {loadError ? (
        <div className={styles.message} role="alert">
          <Icon name="star" size={22} />
          <div>
            <strong>First Times unavailable</strong>
            <p>{loadError}</p>
          </div>
        </div>
      ) : null}

      {!loadError && entries.length === 0 ? (
        <button
          className={styles.emptyState}
          onClick={() => setSelectedEntry(null)}
          type="button"
        >
          <span className={styles.emptyMark}>
            <Icon name="star" size={24} />
          </span>
          <strong>Start with a first worth remembering</strong>
          <span>
            Only a title is required. Dates, notes, and photos can come later.
          </span>
        </button>
      ) : null}

      {!loadError && entries.length > 0 ? (
        <section className={styles.firstGrid} aria-label="First Times archive">
          {visibleEntries.map((entry, index) => (
            <FirstTimeCard
              entry={entry}
              index={index}
              key={entry.id}
              onSelect={() => setSelectedEntry(entry)}
            />
          ))}
        </section>
      ) : null}

      {selectedEntry !== undefined ? (
        <FirstTimeEditor
          collectionOptions={collectionOptions}
          entry={selectedEntry}
          key={selectedEntry?.id ?? "new-first-time"}
          onClose={() => setSelectedEntry(undefined)}
          onSaved={(entry) =>
            setConfirmedEntries((current) => ({
              ...current,
              [entry.id]: entry,
            }))
          }
          ownerId={ownerId}
          tagOptions={tagOptions}
        />
      ) : null}
    </PageFrame>
  );
}

function FirstTimeCard({
  entry,
  index,
  onSelect,
}: {
  entry: FirstTimeEntry;
  index: number;
  onSelect: () => void;
}) {
  const photos = originalAttachments(entry);
  const cover = photos[0];

  return (
    <button
      aria-label={`${entry.title}, ${firstTimeDateLabel(entry)}`}
      className={styles.firstCard}
      onClick={onSelect}
      type="button"
    >
      {cover ? (
        <div className={styles.coverPhoto}>
          {cover.imageUrl ? (
            <ProgressiveImage alt="" src={cover.imageUrl} />
          ) : (
            <span className={styles.coverFallback}>
              <Icon name="photo" size={22} />
              Private photo
            </span>
          )}
          {photos.length > 1 ? <small>{photos.length} photos</small> : null}
        </div>
      ) : (
        <div className={styles.cardIndex} aria-hidden="true">
          {String(index + 1).padStart(2, "0")}
        </div>
      )}

      <div className={styles.cardBody}>
        <time dateTime={entry.occurredStart ?? undefined}>
          {firstTimeDateLabel(entry)}
        </time>
        <h2>{entry.title}</h2>
        {entry.body ? <p>{truncate(entry.body, 180)}</p> : null}
        <footer>
          <div>
            {entry.inboxStatus === "unreviewed" ? <span>In Inbox</span> : null}
            {entry.collectionNames.slice(0, 2).map((name) => (
              <span key={`collection:${name.toLocaleLowerCase()}`}>{name}</span>
            ))}
            {entry.tagNames.slice(0, 2).map((name) => (
              <span key={`tag:${name.toLocaleLowerCase()}`}>#{name}</span>
            ))}
          </div>
          <Icon name="chevron" size={15} />
        </footer>
      </div>
    </button>
  );
}

export function FirstTimeEditor({
  collectionOptions,
  defaultTimezone,
  entry,
  onClose,
  onSaved,
  ownerId,
  tagOptions,
}: {
  collectionOptions: string[];
  defaultTimezone?: string;
  entry: FirstTimeEntry | null;
  onClose: () => void;
  onSaved: (entry: FirstTimeEntry) => void;
  ownerId: string;
  tagOptions: string[];
}) {
  const router = useRouter();
  const titleRef = useRef<HTMLInputElement>(null);
  const [body, setBody] = useState(entry?.body ?? "");
  const [collectionInput, setCollectionInput] = useState("");
  const [collectionNames, setCollectionNames] = useState(
    entry?.collectionNames ?? [],
  );
  const [currentId, setCurrentId] = useState(entry?.id ?? null);
  const [currentRevision, setCurrentRevision] = useState(
    entry?.revision ?? null,
  );
  const [occurrence, setOccurrence] = useState(() =>
    occurrenceDraft(firstTimeOccurrence(entry, defaultTimezone)),
  );
  const [existingPhotos, setExistingPhotos] = useState(
    entry ? originalAttachments(entry) : [],
  );
  const [isPending, setIsPending] = useState(false);
  const [pendingPhotos, setPendingPhotos] = useState<File[]>([]);
  const [result, setResult] = useState<FirstTimeActionResult | null>(null);
  const [tagInput, setTagInput] = useState("");
  const [tagNames, setTagNames] = useState(entry?.tagNames ?? []);
  const [title, setTitle] = useState(entry?.title ?? "");

  useEffect(() => {
    titleRef.current?.focus();
  }, []);

  useEffect(() => {
    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape" && !isPending) {
        onClose();
      }
    }

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [isPending, onClose]);

  function handlePhotoSelection(event: ChangeEvent<HTMLInputElement>) {
    const selected = Array.from(event.target.files ?? []);
    event.target.value = "";

    if (selected.length === 0) {
      return;
    }

    const available = Math.max(
      0,
      firstTimePhotoLimit - existingPhotos.length - pendingPhotos.length,
    );
    const accepted: File[] = [];
    let errorMessage = "";

    for (const file of selected.slice(0, available)) {
      if (!inferFirstTimeImageMimeType(file.name, file.type)) {
        errorMessage = "Use JPEG, PNG, WebP, HEIC, or HEIF photos.";
        continue;
      }

      if (file.size < 1 || file.size > firstTimePhotoSizeLimit) {
        errorMessage = "Each photo must be no larger than 50 MB.";
        continue;
      }

      accepted.push(file);
    }

    if (selected.length > available) {
      errorMessage = `Keep up to ${firstTimePhotoLimit} photos on a First Time.`;
    }

    setPendingPhotos((current) => [...current, ...accepted]);
    setResult(errorMessage ? actionError(errorMessage) : null);
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const resolved = resolveOccurrenceDraft(
      occurrence,
      firstTimeOccurrence(entry),
    );
    if (!resolved.value) {
      setResult(actionError(resolved.error));
      return;
    }
    const input: FirstTimeEntryInput = {
      body,
      collectionNames: namesIncludingDraft(collectionNames, collectionInput),
      datePrecision: resolved.value.datePrecision,
      id: currentId,
      occurredLabel: resolved.value.occurredLabel,
      occurredStart: resolved.value.occurredAt,
      occurredEnd: resolved.value.occurredEnd,
      occurredTimezone: resolved.value.occurredAt
        ? resolved.value.occurredTimezone
        : null,
      revision: currentRevision,
      tagNames: namesIncludingDraft(tagNames, tagInput),
      title,
    };
    const parsed = parseFirstTimeEntryInput(input);

    if (!parsed.success) {
      setResult(actionError(parsed.message));
      return;
    }

    setIsPending(true);
    setResult(null);

    try {
      const saved = await saveFirstTimeEntry(parsed.data);

      if (
        (saved.status !== "created" && saved.status !== "saved") ||
        !saved.entry
      ) {
        setResult(saved);
        return;
      }

      setCurrentId(saved.entry.id);
      setCurrentRevision(saved.entry.revision);
      if (entry && pendingPhotos.length === 0) {
        onSaved({
          ...entry,
          id: saved.entry.id,
          revision: saved.entry.revision,
          title: parsed.data.title,
          body: parsed.data.body,
          collectionNames: parsed.data.collectionNames,
          tagNames: parsed.data.tagNames,
          datePrecision: parsed.data.datePrecision,
          occurredStart: parsed.data.occurredStart,
          occurredEnd: parsed.data.occurredEnd ?? null,
          occurredLabel: parsed.data.occurredLabel,
          occurredTimezone: parsed.data.occurredTimezone,
        });
      }
      const failedPhotos = await uploadPhotos(
        ownerId,
        saved.entry.id,
        pendingPhotos,
      );

      if (failedPhotos.length > 0) {
        setPendingPhotos(failedPhotos);
        setResult(
          actionError(
            `The First Time was saved, but ${countLabel(failedPhotos.length, "photo")} could not be attached. Select Save again to retry.`,
          ),
        );
        router.refresh();
        return;
      }

      router.refresh();
      onClose();
    } catch {
      setResult(
        actionError(
          "MemoTrail could not reach the server. Try again when online.",
        ),
      );
    } finally {
      setIsPending(false);
    }
  }

  async function handleRemovePhoto(photo: FirstTimeAttachment) {
    if (
      !window.confirm(
        "Move this photo to Trash? The original will be preserved.",
      )
    ) {
      return;
    }

    setIsPending(true);
    setResult(null);

    try {
      const nextResult = await trashFirstTimeAttachment({
        attachmentId: photo.id,
      });

      if (nextResult.status === "trashed") {
        setExistingPhotos((current) =>
          current.filter((item) => item.id !== photo.id),
        );
        router.refresh();
      } else {
        setResult(nextResult);
      }
    } catch {
      setResult(
        actionError("MemoTrail could not remove this photo. Try again."),
      );
    } finally {
      setIsPending(false);
    }
  }

  async function handleTrashEntry() {
    if (
      !currentId ||
      currentRevision === null ||
      !window.confirm(
        `Move “${title.trim() || "this First Time"}” to Trash? Its history and private photos will be preserved.`,
      )
    ) {
      return;
    }

    setIsPending(true);
    setResult(null);

    try {
      const nextResult = await trashFirstTimeEntry({
        id: currentId,
        revision: currentRevision,
      });

      if (nextResult.status === "trashed") {
        router.refresh();
        onClose();
      } else {
        setResult(nextResult);
      }
    } catch {
      setResult(
        actionError("MemoTrail could not move this First Time to Trash."),
      );
    } finally {
      setIsPending(false);
    }
  }

  return (
    <div
      aria-labelledby="first-time-editor-title"
      aria-modal="true"
      className={styles.dialogBackdrop}
      onMouseDown={(event) => {
        if (event.currentTarget === event.target && !isPending) {
          onClose();
        }
      }}
      role="dialog"
    >
      <div className={styles.dialogPanel}>
        <header className={styles.dialogHeader}>
          <div>
            <p>{currentId ? "Edit First Time" : "New First Time"}</p>
            <h2 id="first-time-editor-title">
              {currentId ? title || "First Time" : "Keep a beginning"}
            </h2>
          </div>
          <button
            aria-label="Close First Time editor"
            disabled={isPending}
            onClick={onClose}
            type="button"
          >
            ×
          </button>
        </header>

        <form onSubmit={handleSubmit}>
          <div className={styles.formGrid}>
            <label className={styles.fullField}>
              <span>Title</span>
              <input
                maxLength={firstTimeTitleLimit}
                onChange={(event) => setTitle(event.target.value)}
                placeholder="First time skiing"
                ref={titleRef}
                value={title}
              />
            </label>

            <div className={styles.fullField}>
              <OccurrenceEditor
                value={occurrence}
                onChange={setOccurrence}
                disabled={isPending}
              />
            </div>

            <label className={styles.fullField}>
              <span>
                Reflection <small>Optional</small>
              </span>
              <textarea
                maxLength={firstTimeBodyLimit}
                onChange={(event) => setBody(event.target.value)}
                placeholder="What happened, and what do you want to remember?"
                rows={5}
                value={body}
              />
            </label>

            <EntryOrganizationEditor
              disabled={isPending}
              input={collectionInput}
              kind="collection"
              names={collectionNames}
              onChange={setCollectionNames}
              onInputChange={setCollectionInput}
              options={collectionOptions}
            />

            <EntryOrganizationEditor
              disabled={isPending}
              input={tagInput}
              kind="tag"
              names={tagNames}
              onChange={setTagNames}
              onInputChange={setTagInput}
              options={tagOptions}
            />

            <fieldset className={`${styles.photoField} ${styles.fullField}`}>
              <legend>Photos</legend>
              {existingPhotos.length > 0 || pendingPhotos.length > 0 ? (
                <div className={styles.photoGrid}>
                  {existingPhotos.map((photo) => (
                    <div className={styles.photoTile} key={photo.id}>
                      {photo.imageUrl ? (
                        <ProgressiveImage
                          alt={photo.originalFilename ?? "First Time photo"}
                          src={photo.imageUrl}
                        />
                      ) : (
                        <span className={styles.photoFallback}>
                          Private photo
                        </span>
                      )}
                      <button
                        aria-label={`Remove ${photo.originalFilename ?? "photo"}`}
                        disabled={isPending}
                        onClick={() => void handleRemovePhoto(photo)}
                        type="button"
                      >
                        ×
                      </button>
                    </div>
                  ))}
                  {pendingPhotos.map((file, index) => (
                    <PendingPhoto
                      file={file}
                      key={`${file.name}:${file.size}:${file.lastModified}:${index}`}
                      onRemove={() =>
                        setPendingPhotos((current) =>
                          current.filter((_, itemIndex) => itemIndex !== index),
                        )
                      }
                    />
                  ))}
                </div>
              ) : null}
              <label className={styles.photoPicker}>
                <Icon name="photo" size={18} />
                <span>Add photos</span>
                <input
                  accept="image/jpeg,image/png,image/webp,image/heic,image/heif,.heic,.heif"
                  disabled={
                    isPending ||
                    existingPhotos.length + pendingPhotos.length >=
                      firstTimePhotoLimit
                  }
                  multiple
                  onChange={handlePhotoSelection}
                  type="file"
                />
              </label>
              <small>
                Originals stay private. Up to {firstTimePhotoLimit} photos, 50
                MB each.
              </small>
            </fieldset>
          </div>

          {result ? (
            <p className={styles.formMessage} role="alert">
              {result.message}
            </p>
          ) : null}

          <footer className={styles.dialogFooter}>
            <div>
              {currentId ? (
                <button
                  className={styles.trashButton}
                  disabled={isPending}
                  onClick={() => void handleTrashEntry()}
                  type="button"
                >
                  Move to Trash
                </button>
              ) : null}
            </div>
            <div>
              <button
                className={styles.cancelButton}
                disabled={isPending}
                onClick={onClose}
                type="button"
              >
                Cancel
              </button>
              <button
                className={styles.saveButton}
                disabled={isPending}
                type="submit"
              >
                {isPending
                  ? "Saving..."
                  : currentId
                    ? "Save changes"
                    : "Add First Time"}
              </button>
            </div>
          </footer>
        </form>
      </div>
    </div>
  );
}

function PendingPhoto({
  file,
  onRemove,
}: {
  file: File;
  onRemove: () => void;
}) {
  const [previewUrl] = useState(() => URL.createObjectURL(file));

  useEffect(() => {
    return () => URL.revokeObjectURL(previewUrl);
  }, [previewUrl]);

  return (
    <div className={`${styles.photoTile} ${styles.pendingPhoto}`}>
      <ProgressiveImage alt={`Selected ${file.name}`} src={previewUrl} />
      <span className={styles.pendingBadge}>New</span>
      <button
        aria-label={`Remove selected ${file.name}`}
        onClick={onRemove}
        type="button"
      >
        ×
      </button>
    </div>
  );
}

async function uploadPhotos(ownerId: string, entryId: string, photos: File[]) {
  return uploadEntryPhotos(
    ownerId,
    entryId,
    photos,
    registerFirstTimeAttachment,
  );
}

function originalAttachments(entry: FirstTimeEntry) {
  return entry.attachments.filter(
    (attachment) => attachment.variant === "original",
  );
}

function firstTimeOccurrence(
  entry: FirstTimeEntry | null,
  defaultTimezone?: string,
): Occurrence {
  return {
    occurredAt: entry?.occurredStart ?? null,
    occurredEnd: entry?.occurredEnd ?? null,
    datePrecision: entry?.datePrecision ?? "unknown",
    occurredLabel: entry?.occurredLabel ?? null,
    occurredTimezone:
      entry?.occurredTimezone ?? defaultTimezone ?? localTimezone(),
  };
}
function firstTimeDateLabel(entry: FirstTimeEntry) {
  return occurrenceLabel(firstTimeOccurrence(entry));
}

function localTimezone() {
  return Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
}

function namesIncludingDraft(names: string[], draft: string) {
  const name = draft.trim();
  return name ? [...names, name] : names;
}

function countLabel(count: number, singular: string) {
  return `${count} ${count === 1 ? singular : `${singular}s`}`;
}

function truncate(value: string, limit: number) {
  return value.length > limit ? `${value.slice(0, limit).trimEnd()}…` : value;
}

function actionError(message: string): FirstTimeActionResult {
  return { entry: null, message, status: "error" };
}
