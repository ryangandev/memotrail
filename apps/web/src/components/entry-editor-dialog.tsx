"use client";
import { notify } from "@/components/app-toast";
import styles from "@/components/entry-editor-dialog.module.css";
import entryFormStyles from "@/components/entry-form.module.css";
import { Dialog } from "@/components/dialog";
import { Button } from "@/components/button";
import type { PhotoLocationDraft } from "@/lib/media/photo-location";

import { useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import {
  reviewInboxEntry,
  type ReviewInboxEntryResult,
} from "@/app/inbox/actions";
import { EntryOrganizationEditor } from "@/components/entry-organization-editor";
import { OccurrenceEditor } from "@/components/occurrence-editor";
import { EntryPhotoDates } from "@/components/entry-photo-dates";
import { RichTextEditor } from "@/components/rich-text-editor";
import { LocationPicker } from "@/components/location-picker";
import type { LocationSelection } from "@/lib/locations/location";
import { photoCalendarDateDraft } from "@/lib/media/photo-metadata";
import { occurrenceDraft, resolveOccurrenceDraft } from "@/lib/data/occurrence";
import type { InboxEntry } from "@/lib/data/inbox";
import { entryBodyLimit, entryTitleLimit } from "@/lib/data/inbox-input";
import {
  parseInboxReviewInput,
  type InboxReviewInput,
} from "@/lib/data/inbox-review";
import { trimEntryNote } from "@/lib/data/rich-text";

export function EntryEditorDialog({
  entry,
  onClose,
  onSaved,
  tagOptions,
}: {
  entry: InboxEntry;
  onClose: () => void;
  onSaved: (entry: InboxEntry) => void;
  tagOptions: string[];
}) {
  const router = useRouter();
  const [title, setTitle] = useState(entry.title ?? "");
  const [body, setBody] = useState(entry.body);
  const [bodyRich, setBodyRich] = useState(entry.bodyRich);
  const [location, setLocation] = useState<LocationSelection | null>(
    entry.location ?? null,
  );
  const [occurrence, setOccurrence] = useState(() => occurrenceDraft(entry));
  const [photoLocation, setPhotoLocation] = useState<PhotoLocationDraft | null>(
    null,
  );
  const [isPending, setIsPending] = useState(false);
  const [result, setResult] = useState<ReviewInboxEntryResult | null>(null);
  const [tagNames, setTagNames] = useState(entry.tagNames);
  const [tagInput, setTagInput] = useState("");

  async function save() {
    const resolved = resolveOccurrenceDraft(occurrence, entry);
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
      revision: entry.revision,
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
        onSaved({
          ...entry,
          ...parsedInput.data,
          datePrecision: parsedInput.data.datePrecision ?? "exact",
          occurredEnd: parsedInput.data.occurredEnd ?? null,
          occurredLabel: parsedInput.data.occurredLabel ?? null,
          revision: nextResult.revision,
        });
        router.refresh();
        notify.success("Entry saved.");
        return;
      }

      setResult(nextResult);
    } catch {
      setResult({
        message: "MemoTrail could not reach the server. Try again when online.",
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
      title={<>Edit Entry</>}
      titleId="entry-editor-heading"
      eyebrow={<>Life Wiki editor</>}
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
            {isPending ? "Saving…" : "Save changes"}
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

        <OccurrenceEditor
          value={occurrence}
          onChange={setOccurrence}
          disabled={isPending}
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

        <EntryPhotoDates
          photoLocation={photoLocation}
          onPhotoLocationChange={setPhotoLocation}
          entryId={entry.id}
          disabled={isPending}
          onUseDate={(date) =>
            setOccurrence((current) => photoCalendarDateDraft(date, current))
          }
        />

        {result ? (
          <p className={styles.error} role="alert">
            {result.message}
          </p>
        ) : null}
      </form>
    </Dialog>
  );
}

function namesIncludingDraft(names: string[], draft: string) {
  const name = draft.trim();
  return name ? [...names, name] : names;
}
