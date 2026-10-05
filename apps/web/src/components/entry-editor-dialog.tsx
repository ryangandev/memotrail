"use client";
import { notify } from "@/components/app-toast";
import styles from "@/components/entry-editor-dialog.module.css";
import entryFormStyles from "@/components/entry-form.module.css";
import { Dialog } from "@/components/dialog";
import { Button } from "@/components/button";
import { useConfirmationDialog } from "@/components/confirmation-dialog";
import { EntryPhotoField } from "@/components/entry-photo-field";
import type { PhotoLocationDraft } from "@/lib/media/photo-location";

import { useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import {
  registerEntryAttachment,
  reviewInboxEntry,
  type ReviewInboxEntryResult,
} from "@/app/inbox/actions";
import { trashEntryPhoto } from "@/app/items/media-actions";
import { EntryOrganizationEditor } from "@/components/entry-organization-editor";
import { OccurrenceEditor } from "@/components/occurrence-editor";
import { EntryPhotoDates } from "@/components/entry-photo-dates";
import { RichTextEditor } from "@/components/rich-text-editor";
import { LocationPicker } from "@/components/location-picker";
import { MilestoneFields } from "@/components/milestone-fields";
import type { Milestone } from "@/lib/data/milestone";
import type { LocationSelection } from "@/lib/locations/location";
import {
  photoCalendarDateDraft,
  type EntryPhoto,
} from "@/lib/media/photo-metadata";
import {
  uploadEntryPhotos,
  type PhotoUploadProgress,
} from "@/lib/media/upload";
import {
  entryPhotoLimit,
  type EntryAttachmentInput,
} from "@/lib/data/entry-photo-input";
import { validateInboxPhotoFiles } from "@/lib/data/inbox-photo";
import { occurrenceDraft, resolveOccurrenceDraft } from "@/lib/data/occurrence";
import type { InboxEntry } from "@/lib/data/inbox";
import { entryBodyLimit, entryTitleLimit } from "@/lib/data/inbox-input";
import {
  parseInboxReviewInput,
  type InboxReviewInput,
} from "@/lib/data/inbox-review";
import { trimEntryNote } from "@/lib/data/rich-text";

// A new Entry for the editor's create mode, such as a milestone added from Timeline.
// Adds a new Entry. Its id is drafted once, so a retried save cannot add it twice.
export function NewEntryDialog({
  milestone,
  onClose,
  ownerId,
  tagOptions,
  timezone,
}: {
  milestone: Milestone | null;
  onClose: () => void;
  ownerId: string;
  tagOptions: string[];
  timezone: string;
}) {
  const [entry] = useState(() => newEntryDraft({ milestone, timezone }));
  return (
    <EntryEditorDialog
      defaultTimezone={timezone}
      entry={entry}
      isNew
      onClose={onClose}
      onSaved={onClose}
      ownerId={ownerId}
      photos={[]}
      tagOptions={tagOptions}
    />
  );
}

function newEntryDraft({
  milestone,
  timezone,
}: {
  milestone: Milestone | null;
  timezone: string;
}): InboxEntry {
  return {
    body: "",
    bodyRich: null,
    createdAt: new Date().toISOString(),
    datePrecision: "unknown",
    id: crypto.randomUUID(),
    itemKind: "entry",
    itemSubtype: "entry",
    location: null,
    milestone,
    occurredAt: null,
    occurredEnd: null,
    occurredLabel: null,
    occurredTimezone: timezone,
    revision: 0,
    tagNames: [],
    title: null,
  };
}

export function EntryEditorDialog({
  defaultTimezone,
  entry,
  isNew = false,
  onClose,
  onSaved,
  ownerId,
  photos,
  tagOptions,
}: {
  // The time zone from Settings, shown as the default for a new Entry.
  defaultTimezone?: string;
  entry: InboxEntry;
  // Saves `entry` as a new Entry. Use `NewEntryDialog` to add one.
  isNew?: boolean;
  onClose: () => void;
  onSaved: (entry: InboxEntry) => void;
  ownerId: string;
  // The Entry's saved photos when the editor opened.
  photos: EntryPhoto[];
  tagOptions: string[];
}) {
  const router = useRouter();
  const requestConfirmation = useConfirmationDialog();
  const [title, setTitle] = useState(entry.title ?? "");
  const [body, setBody] = useState(entry.body);
  const [bodyRich, setBodyRich] = useState(entry.bodyRich);
  const [location, setLocation] = useState<LocationSelection | null>(
    entry.location ?? null,
  );
  const [occurrence, setOccurrence] = useState(() => occurrenceDraft(entry));
  const [milestone, setMilestone] = useState<Milestone | null>(
    entry.milestone ?? null,
  );
  const [photoLocation, setPhotoLocation] = useState<PhotoLocationDraft | null>(
    null,
  );
  const [isPending, setIsPending] = useState(false);
  const [result, setResult] = useState<ReviewInboxEntryResult | null>(null);
  const [tagNames, setTagNames] = useState(entry.tagNames);
  const [tagInput, setTagInput] = useState("");
  const [existingPhotos, setExistingPhotos] = useState(photos);
  const [pendingPhotos, setPendingPhotos] = useState<File[]>([]);
  const [photoProgress, setPhotoProgress] =
    useState<PhotoUploadProgress | null>(null);
  // Once a new Entry is saved, Save again updates it, such as to retry its photos.
  const [revision, setRevision] = useState<number | null>(
    isNew ? null : entry.revision,
  );

  function changeMilestone(next: Milestone | null) {
    // Only a Period can be still going on or end on a calendar date, and a Moment is one
    // point in time, so leaving a Period drops its end. A plain Entry keeps a date range.
    if (next?.shape !== "period")
      setOccurrence((value) =>
        !next && value.precision === "range"
          ? value
          : {
              ...value,
              end: "",
              endMode: "date",
              precision: value.precision === "range" ? "day" : value.precision,
            },
      );
    setMilestone(next);
    setResult(null);
  }

  async function save() {
    const resolved = resolveOccurrenceDraft(
      occurrence,
      isNew ? undefined : entry,
      milestone?.shape === "period",
    );
    if (resolved.error) {
      setResult({ message: resolved.error, status: "error" });
      return;
    }
    const note = trimEntryNote(body, bodyRich);
    const input: InboxReviewInput = {
      location,
      photoLocation,
      ...resolved.value!,
      body: note.body,
      bodyRich: note.bodyRich,
      id: entry.id,
      milestone,
      revision,
      tagNames: namesIncludingDraft(tagNames, tagInput),
      title: title || null,
    };
    const parsedInput = parseInboxReviewInput(input);

    if (!parsedInput.success) {
      setResult({ message: parsedInput.message, status: "error" });
      return;
    }

    setIsPending(true);
    setResult(null);

    try {
      const nextResult = await reviewInboxEntry(parsedInput.data);

      if (nextResult.status === "saved") {
        setRevision(nextResult.revision);
        const failedPhotos = await uploadEntryPhotos(
          ownerId,
          entry.id,
          pendingPhotos,
          registerPhoto,
          setPhotoProgress,
        );
        if (failedPhotos.length > 0) {
          setPendingPhotos(failedPhotos);
          setResult({
            message: `The Entry was saved, but ${failedPhotos.length === 1 ? "1 photo" : `${failedPhotos.length} photos`} could not be attached. Select Save again to retry.`,
            status: "error",
          });
          router.refresh();
          return;
        }
        onSaved({
          ...entry,
          ...parsedInput.data,
          datePrecision: parsedInput.data.datePrecision ?? "exact",
          occurredEnd: parsedInput.data.occurredEnd ?? null,
          occurredLabel: parsedInput.data.occurredLabel ?? null,
          revision: nextResult.revision,
        });
        router.refresh();
        notify.success(
          !isNew
            ? "Entry saved."
            : milestone?.isFirstTime
              ? "First Time added."
              : milestone
                ? "Added to Timeline."
                : "Entry added.",
        );
        return;
      }

      setResult(nextResult);
    } catch {
      setResult({
        message: "MemoTrail could not reach the server. Try again when online.",
        status: "error",
      });
    } finally {
      setPhotoProgress(null);
      setIsPending(false);
    }
  }

  function selectPhotos(files: File[]) {
    const selection = validateInboxPhotoFiles(
      files,
      existingPhotos.length + pendingPhotos.length,
    );
    setPendingPhotos((current) => [
      ...current,
      ...selection.accepted.map((draft) => draft.file),
    ]);
    setResult(
      selection.message
        ? { message: selection.message, status: "error" }
        : null,
    );
  }

  async function removePhoto(photo: EntryPhoto) {
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
      if (!(await trashEntryPhoto(entry.id, photo.id))) throw Error();
      setExistingPhotos((current) =>
        current.filter((item) => item.id !== photo.id),
      );
      router.refresh();
      notify.info("Photo moved to Trash.");
    } catch {
      setResult({
        message: "MemoTrail could not remove this photo. Try again.",
        status: "error",
      });
    } finally {
      setIsPending(false);
    }
  }

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    void save();
  }

  return (
    <Dialog
      open
      onOpenChange={(nextOpen) => {
        if (!nextOpen) onClose();
      }}
      title={
        isNew ? (
          <>
            {entry.milestone?.isFirstTime
              ? "Add a First Time"
              : "Add a milestone"}
          </>
        ) : (
          <>Edit Entry</>
        )
      }
      titleId="entry-editor-heading"
      eyebrow={isNew ? <>New Entry</> : <>Life Wiki editor</>}
      closeLabel="Close Entry editor"
      busy={isPending}
      size="wide"
      footer={
        <div className={styles.actions}>
          <Button
            variant="secondary"
            disabled={isPending}
            onClick={onClose}
            type="button"
          >
            Cancel
          </Button>
          <Button
            form="entry-editor-form"
            variant="primary"
            disabled={isPending}
            type="submit"
          >
            {isPending ? "Saving…" : isNew ? "Add" : "Save changes"}
          </Button>
        </div>
      }
    >
      <form
        id="entry-editor-form"
        className={entryFormStyles.reviewForm}
        onSubmit={handleSubmit}
      >
        <label>
          <span>Title</span>
          <input
            aria-label="Title"
            autoFocus
            disabled={isPending}
            maxLength={entryTitleLimit}
            onChange={(event) => setTitle(event.target.value)}
            placeholder="Add a title"
            value={title}
          />
        </label>

        <div className={styles.richTextField}>
          <span>Note</span>
          <RichTextEditor
            disabled={isPending}
            maxLength={entryBodyLimit}
            label="Note"
            onChange={(value) => {
              setBody(value.text);
              setBodyRich(value);
            }}
            placeholder="Write what you want to remember"
            richText={bodyRich}
            text={body}
            variant="form"
          />
        </div>

        <EntryPhotoField
          disabled={isPending}
          existingPhotos={existingPhotos.map((photo) => ({
            ...photo,
            originalFilename: photo.name,
          }))}
          limit={entryPhotoLimit}
          onRemoveExisting={(photo) => void removePhoto(photo)}
          onRemovePending={(index) =>
            setPendingPhotos((current) =>
              current.filter((_, position) => position !== index),
            )
          }
          onSelect={selectPhotos}
          pendingPhotos={pendingPhotos}
          progress={photoProgress}
          recordLabel="Entry"
        />

        <MilestoneFields
          disabled={isPending}
          onChange={changeMilestone}
          value={milestone}
        />

        <OccurrenceEditor
          defaultTimezone={defaultTimezone}
          value={occurrence}
          onChange={setOccurrence}
          disabled={isPending}
          span={milestone?.shape === "period"}
          point={milestone?.shape === "moment"}
        />

        <LocationPicker
          disabled={isPending}
          onChange={setLocation}
          value={location}
        />

        <EntryOrganizationEditor
          disabled={isPending}
          names={tagNames}
          onChange={setTagNames}
          input={tagInput}
          onInputChange={setTagInput}
          options={tagOptions}
        />

        {existingPhotos.length > 0 ? (
          <EntryPhotoDates
            photoLocation={photoLocation}
            onPhotoLocationChange={setPhotoLocation}
            photos={existingPhotos}
            disabled={isPending}
            onUseDate={(date) =>
              setOccurrence((current) => photoCalendarDateDraft(date, current))
            }
          />
        ) : null}

        {result ? (
          <p className={styles.error} role="alert">
            {result.message}
          </p>
        ) : null}
      </form>
    </Dialog>
  );
}

async function registerPhoto(input: EntryAttachmentInput) {
  const result = await registerEntryAttachment(input);
  return { status: result.status === "synced" ? "saved" : "error" };
}

function namesIncludingDraft(names: string[], draft: string) {
  const name = draft.trim();
  return name ? [...names, name] : names;
}
