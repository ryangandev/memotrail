"use client";
import { Dialog } from "@/components/dialog";
import { useConfirmationDialog } from "@/components/confirmation-dialog";
import { EmptyState } from "@/components/empty-state";
import { FocusedViewLayout } from "@/components/focused-view-layout";
import { Button } from "@/components/button";

import { useEffect, useRef, useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import {
  registerFirstTimeAttachment,
  saveFirstTimeEntry,
  trashFirstTimeAttachment,
  trashFirstTimeEntry,
  type FirstTimeActionResult,
} from "@/app/first-times/actions";
import styles from "@/components/first-times-workspace.module.css";
import { EntryPhotoField } from "@/components/entry-photo-field";
import { EntryOrganizationEditor } from "@/components/entry-organization-editor";
import { LocationPicker } from "@/components/location-picker";
import { Icon } from "@/components/icon";
import { ProgressiveImage } from "@/components/progressive-image";
import { RecordCardMap } from "@/components/record-card-map";
import {
  RecordCard,
  RecordCardBody,
  RecordCardVisual,
} from "@/components/record-card";
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
import {
  uploadEntryPhotos,
  type PhotoUploadProgress as PhotoUploadProgressValue,
} from "@/lib/media/upload";
import type { LocationSelection } from "@/lib/locations/location";

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
    <FocusedViewLayout
      actions={
        <Button
          variant="primary"
          aria-label="Add First Time"
          onClick={() => setSelectedEntry(null)}
          type="button"
        >
          <Icon name="plus" />
          <span>Add First Time</span>
        </Button>
      }
      description={
        <>Keep the small beginnings and major milestones worth finding again.</>
      }
      eyebrow={<>A record of beginnings</>}
      summary={
        <>
          <span>{countLabel(entries.length, "First Time")}</span>
          <span aria-hidden="true">·</span>
          <span>{countLabel(photoCount, "photo")}</span>
        </>
      }
      summaryLabel="First Times summary"
      title={<>First Times</>}
    >
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
        <EmptyState
          title={<>Start with a first worth remembering</>}
          icon={
            <>
              <Icon name="star" size={24} />
            </>
          }
          description={
            <>
              Only a title is required. Dates, notes, and photos can come later.
            </>
          }
          onClick={() => setSelectedEntry(null)}
        />
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
    </FocusedViewLayout>
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
    <RecordCard
      ariaLabel={`${entry.title}, ${firstTimeDateLabel(entry)}`}
      className={styles.firstCard}
      onClick={onSelect}
    >
      {cover ? (
        <RecordCardVisual className={styles.coverPhoto}>
          {cover.imageUrl ? (
            <ProgressiveImage alt="" src={cover.imageUrl} />
          ) : (
            <span className={styles.coverFallback}>
              <Icon name="photo" size={22} />
              Private photo
            </span>
          )}
          {photos.length > 1 ? <small>{photos.length} photos</small> : null}
        </RecordCardVisual>
      ) : (
        <RecordCardVisual className={styles.coverPhoto}>
          <RecordCardMap
            eager={index < 4}
            fallback={
              <span className={styles.cardIndexFallback}>
                {String(index + 1).padStart(2, "0")}
              </span>
            }
            latitude={entry.location?.latitude}
            longitude={entry.location?.longitude}
          />
        </RecordCardVisual>
      )}

      <RecordCardBody className={styles.cardBody}>
        <time dateTime={entry.occurredStart ?? undefined}>
          {firstTimeDateLabel(entry)}
        </time>
        <h2>{entry.title}</h2>
        {entry.location ? (
          <p className={styles.locationLine}>
            <Icon name="map" size={14} />
            {entry.location.name}
          </p>
        ) : null}
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
      </RecordCardBody>
    </RecordCard>
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
  const requestConfirmation = useConfirmationDialog();
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
  const [location, setLocation] = useState<LocationSelection | null>(
    entry?.location ?? null,
  );
  const [locationDirty, setLocationDirty] = useState(false);
  const [occurrence, setOccurrence] = useState(() =>
    occurrenceDraft(firstTimeOccurrence(entry, defaultTimezone)),
  );
  const [existingPhotos, setExistingPhotos] = useState(
    entry ? originalAttachments(entry) : [],
  );
  const [isPending, setIsPending] = useState(false);
  const [photoUploadProgress, setPhotoUploadProgress] =
    useState<PhotoUploadProgressValue | null>(null);
  const [pendingPhotos, setPendingPhotos] = useState<File[]>([]);
  const [result, setResult] = useState<FirstTimeActionResult | null>(null);
  const [tagInput, setTagInput] = useState("");
  const [tagNames, setTagNames] = useState(entry?.tagNames ?? []);
  const [title, setTitle] = useState(entry?.title ?? "");

  useEffect(() => {
    titleRef.current?.focus();
  }, []);

  function handlePhotoSelection(selected: File[]) {
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
      const saved = await saveFirstTimeEntry(
        parsed.data,
        locationDirty ? location : undefined,
      );

      if (
        (saved.status !== "created" && saved.status !== "saved") ||
        !saved.entry
      ) {
        setResult(saved);
        return;
      }

      setCurrentId(saved.entry.id);
      setCurrentRevision(saved.entry.revision);
      setLocationDirty(false);
      if (entry && pendingPhotos.length === 0) {
        onSaved({
          ...entry,
          id: saved.entry.id,
          revision: saved.entry.revision,
          title: parsed.data.title,
          body: parsed.data.body,
          location,
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
        setPhotoUploadProgress,
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
      setPhotoUploadProgress(null);
      setIsPending(false);
    }
  }

  async function handleRemovePhoto(photo: FirstTimeAttachment) {
    const confirmed = await requestConfirmation({
      title: <>Move this photo to Trash?</>,
      description: <>The original will be preserved for recovery.</>,
      confirmLabel: "Move photo to Trash",
      eyebrow: <>Recoverable action</>,
      variant: "danger",
    });
    if (!confirmed) return;

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
    if (!currentId || currentRevision === null) return;
    const confirmed = await requestConfirmation({
      title: <>Move “{title.trim() || "this First Time"}” to Trash?</>,
      description: <>Its history and private photos will be preserved.</>,
      confirmLabel: "Move to Trash",
      eyebrow: <>Recoverable action</>,
      variant: "danger",
    });
    if (!confirmed) return;

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
    <Dialog
      open
      onOpenChange={(nextOpen) => {
        if (!nextOpen) onClose();
      }}
      title={<>{currentId ? title || "First Time" : "Keep a beginning"}</>}
      titleId="first-time-editor-title"
      eyebrow={<>{currentId ? "Edit First Time" : "New First Time"}</>}
      closeLabel="Close First Time editor"
      busy={isPending}
      size="wide"
      footer={
        <div className={styles.dialogFooter}>
          <div>
            {currentId ? (
              <Button
                variant="danger"
                disabled={isPending}
                onClick={() => void handleTrashEntry()}
                type="button"
              >
                Move to Trash
              </Button>
            ) : null}
          </div>
          <div>
            <Button
              variant="secondary"
              disabled={isPending}
              onClick={onClose}
              type="button"
            >
              Cancel
            </Button>
            <Button
              form="first-times-workspace-form"
              variant="primary"
              disabled={isPending}
              type="submit"
            >
              {isPending
                ? "Saving..."
                : currentId
                  ? "Save changes"
                  : "Add First Time"}
            </Button>
          </div>
        </div>
      }
    >
      {" "}
      <form id="first-times-workspace-form" onSubmit={handleSubmit}>
        <div className={styles.formGrid}>
          <label className={styles.fullField}>
            <span>
              Title <span aria-hidden="true">*</span>
            </span>
            <input
              aria-label="Title"
              maxLength={firstTimeTitleLimit}
              onChange={(event) => setTitle(event.target.value)}
              placeholder="First time skiing"
              ref={titleRef}
              required
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

          <div className={styles.fullField}>
            <LocationPicker
              disabled={isPending}
              onChange={(selection) => {
                setLocation(selection);
                setLocationDirty(true);
              }}
              value={location}
            />
          </div>

          <label className={styles.fullField}>
            <span>Reflection</span>
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

          <EntryPhotoField
            disabled={isPending}
            existingPhotos={existingPhotos}
            limit={firstTimePhotoLimit}
            onRemoveExisting={(photo) => void handleRemovePhoto(photo)}
            onRemovePending={(index) =>
              setPendingPhotos((current) =>
                current.filter((_, itemIndex) => itemIndex !== index),
              )
            }
            onSelect={handlePhotoSelection}
            pendingPhotos={pendingPhotos}
            progress={photoUploadProgress}
            recordLabel="First Time"
          />
        </div>

        {result ? (
          <p className={styles.formMessage} role="alert">
            {result.message}
          </p>
        ) : null}
      </form>
    </Dialog>
  );
}

async function uploadPhotos(
  ownerId: string,
  entryId: string,
  photos: File[],
  onProgress: (progress: PhotoUploadProgressValue) => void,
) {
  return uploadEntryPhotos(
    ownerId,
    entryId,
    photos,
    registerFirstTimeAttachment,
    onProgress,
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
