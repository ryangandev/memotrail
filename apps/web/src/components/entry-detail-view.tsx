"use client";
import { notify } from "@/components/app-toast";
import { PageHeader } from "@/components/page-header";
import { Button, ButtonLink } from "@/components/button";
import { useConfirmationDialog } from "@/components/confirmation-dialog";
import Link from "next/link";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { EntryEditorDialog } from "./entry-editor-dialog";
import { EntryPhotos } from "./entry-photos";
import { EntryRichTextContent } from "./entry-rich-text-content";
import { Icon } from "./icon";
import { DatePickerField } from "./date-picker-field";
import {
  extractGoalFromItem,
  loadEditableEntry,
  trashWikiItem,
} from "@/app/items/actions";
import {
  entryDateLabel,
  entryTitle,
  type EntryDetail,
} from "@/lib/data/entry-detail";
import { wikiItemIdentityLabel, wikiItemKindLabel } from "@/lib/data/wiki-item";
import type { EntryPhotos as EntryPhotoList } from "@/lib/data/entry-photos";
import { locationDisplayLabel } from "@/lib/locations/location";
import { timelineLaneLabels } from "@/lib/data/milestone";
import styles from "@/components/entry-detail-view.module.css";

const sourceLinkLabels: Record<string, string> = {
  derived: "Open extracted item",
  derived_from: "Open source item",
  exploration_source: "Open source item",
  exploration_conclusion: "Open saved conclusion",
};

export function EntryDetailView({
  entry,
  ownerId,
  photos,
}: {
  entry: EntryDetail;
  ownerId: string;
  // Null when the item is in Trash or its photos could not load.
  photos: EntryPhotoList | null;
}) {
  const router = useRouter();
  const requestConfirmation = useConfirmationDialog();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [editing, setEditing] =
    useState<Awaited<ReturnType<typeof loadEditableEntry>>>(null);
  const active = !entry.deleted_at;
  async function edit() {
    setBusy(true);
    setError(null);
    try {
      const data = await loadEditableEntry(entry.id);
      if (!data) throw Error();
      setEditing(data);
    } catch {
      setError("This item cannot be edited right now. Refresh and try again.");
    } finally {
      setBusy(false);
    }
  }
  async function moveToTrash() {
    if (busy) return;
    const confirmed = await requestConfirmation({
      title: <>Move “{entryTitle(entry)}” to Trash?</>,
      description: <>You can restore it later from Trash.</>,
      confirmLabel: "Move to Trash",
      eyebrow: <>Recoverable action</>,
      variant: "danger",
    });
    if (!confirmed) return;

    setBusy(true);
    setError(null);
    try {
      const message = await trashWikiItem(entry.id, entry.revision);
      if (message) setError(message);
      else {
        router.push("/library");
        router.refresh();
        notify.info("Entry moved to Trash.");
      }
    } catch {
      setError(
        "Could not confirm the move to Trash. Refresh before trying again.",
      );
    } finally {
      setBusy(false);
    }
  }
  return (
    <>
      <Link className={styles.backLink} href="/library">
        ← Library
      </Link>
      <PageHeader title={<>{entryTitle(entry)}</>} />
      <div className={styles.itemActions}>
        {active && entry.item_kind === "entry" && (
          <Button
            variant="secondary"
            type="submit"
            disabled={busy}
            onClick={() => void edit()}
          >
            Edit {wikiItemKindLabel(entry.item_kind)}
          </Button>
        )}
        {editing && (
          <EntryEditorDialog
            entry={editing.entry}
            ownerId={ownerId}
            photos={editing.photos}
            tagOptions={editing.tagOptions}
            onClose={() => setEditing(null)}
            onSaved={() => {
              setEditing(null);
              router.refresh();
            }}
          />
        )}
        {active && entry.item_kind !== "goal" && (
          <GoalExtraction
            key={`${entry.id}:${entry.revision}`}
            entry={entry}
            disabled={busy}
            onBusyChange={setBusy}
          />
        )}
        {active && entry.item_kind === "goal" && (
          <ButtonLink href={`/goals/${entry.id}`}>
            Open in Want to Do
          </ButtonLink>
        )}
        {active ? (
          <Button
            variant="danger"
            className={styles.trashAction}
            disabled={busy}
            onClick={() => void moveToTrash()}
            type="button"
          >
            <Icon name="trash" size={16} />
            Move to Trash
          </Button>
        ) : null}
      </div>
      {error && <p role="alert">{error}</p>}
      {entry.links.map((link) =>
        sourceLinkLabels[link.relationship] ? (
          <p key={`${link.relationship}:${link.target_entry_id}`}>
            <Link href={`/items/${link.target_entry_id}`}>
              {sourceLinkLabels[link.relationship]}
            </Link>
          </p>
        ) : null,
      )}
      {!active && (
        <p role="status">
          This item is in Trash. Restore it there to change it.
        </p>
      )}
      <CurrentItem
        photos={active ? photos : { hasMore: false, photos: [] }}
        value={entry}
      />
    </>
  );
}

function CurrentItem({
  photos,
  value,
}: {
  photos: EntryPhotoList | null;
  value: EntryDetail;
}) {
  const groups = [
    { key: "tags", label: "tags", names: value.tags.map((tag) => tag.name) },
    {
      key: "locations",
      label: "locations",
      names: value.locations.map((location) =>
        locationDisplayLabel({
          formattedAddress: location.formatted_address,
          latitude: location.latitude,
          longitude: location.longitude,
        }),
      ),
    },
    {
      key: "timeline",
      label: "timeline",
      names: value.milestone
        ? [
            [
              value.milestone.is_first_time ? "First Time" : null,
              value.milestone.shape === "period" ? "Period" : "Moment",
              timelineLaneLabels[value.milestone.lane],
            ]
              .filter(Boolean)
              .join(" · "),
          ]
        : [],
    },
  ]
    .filter((group) => group.names.length > 0)
    .map((group) => ({ ...group, value: group.names.join(", ") }));

  return (
    <article className={styles.currentItem} aria-label="Current item">
      <EntryRichTextContent
        body={value.body || "No writing has been added yet."}
        className={styles.currentBody}
        metadata={value.body ? value.metadata : undefined}
      />
      {photos === null ? (
        <p className={styles.photosError} role="alert">
          Photos could not load. Refresh the page to try again.
        </p>
      ) : photos.photos.length > 0 ? (
        <EntryPhotos hasMore={photos.hasMore} photos={photos.photos} />
      ) : null}
      <dl className={styles.currentFacts}>
        {value.item_kind !== "entry" || value.item_subtype !== "entry" ? (
          <div>
            <dt>Record</dt>
            <dd>
              {wikiItemIdentityLabel(value.item_kind, value.item_subtype)}
            </dd>
          </div>
        ) : null}
        <div>
          <dt>Date</dt>
          <dd>{entryDateLabel(value)}</dd>
        </div>
        {groups.map((group) => (
          <div key={group.key}>
            <dt>{group.label}</dt>
            <dd>{group.value}</dd>
          </div>
        ))}
      </dl>
    </article>
  );
}
function GoalExtraction({
  entry,
  disabled,
  onBusyChange,
}: {
  entry: EntryDetail;
  disabled: boolean;
  onBusyChange: (busy: boolean) => void;
}) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [goalId, setGoalId] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [title, setTitle] = useState(entry.title ?? "");
  const [targetDate, setTargetDate] = useState("");
  const [error, setError] = useState<string | null>(null);
  if (!open)
    return (
      <Button
        variant="secondary"
        type="button"
        disabled={disabled}
        onClick={() => {
          setGoalId(crypto.randomUUID());
          setOpen(true);
        }}
      >
        Add to Want to Do
      </Button>
    );
  return (
    <form
      aria-label="Add to Want to Do"
      className={styles.conversion}
      onSubmit={async (event) => {
        event.preventDefault();
        setBusy(true);
        onBusyChange(true);
        setError(null);
        try {
          if (!goalId) throw Error("Missing Want to Do identity");
          const result = await extractGoalFromItem({
            goalId,
            sourceId: entry.id,
            sourceRevision: entry.revision,
            title,
            targetDate: targetDate || null,
          });
          if (result.error) setError(result.error);
          else if (result.goalId) {
            setOpen(false);
            router.push(`/goals/${result.goalId}`);
          }
        } catch {
          setError(
            "Could not confirm it was added. Refresh to check the source before retrying.",
          );
        } finally {
          setBusy(false);
          onBusyChange(false);
        }
      }}
    >
      <h3>Add this to Want to Do</h3>
      <p>
        This adds a separate item to Want to Do and links it back to this
        source. The source keeps its writing, dates, and photos.
      </p>
      <fieldset disabled={busy || disabled}>
        <label>
          <span>
            What do you want to do? <span aria-hidden="true">*</span>
          </span>
          <input
            aria-label="What do you want to do?"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            maxLength={200}
            required
          />
        </label>
        <DatePickerField
          disabled={busy}
          label="Target date"
          value={targetDate}
          onChange={setTargetDate}
        />
        <div className={styles.controls}>
          <Button
            variant="secondary"
            type="button"
            onClick={() => {
              setOpen(false);
              setGoalId(null);
            }}
          >
            Cancel
          </Button>
          <Button variant="primary" type="submit">
            {busy ? "Adding..." : "Add to Want to Do"}
          </Button>
        </div>
      </fieldset>
      {error && <p role="alert">{error}</p>}
    </form>
  );
}
