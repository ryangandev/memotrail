"use client";
import { Button } from "@/components/button";
import type { PhotoPlaceDraft } from "@/lib/media/photo-place";

import { useEffect, useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import {
  reviewInboxEntry,
  type ReviewInboxEntryResult,
} from "@/app/inbox/actions";
import { Icon } from "@/components/icon";
import { EntryAISuggestionsPanel } from "@/components/entry-ai-suggestions";
import { EntryOrganizationEditor } from "@/components/entry-organization-editor";
import { OccurrenceEditor } from "@/components/occurrence-editor";
import { EntryPhotoDates } from "@/components/entry-photo-dates";
import { RichTextEditor } from "@/components/rich-text-editor";
import { photoCalendarDateDraft } from "@/lib/media/photo-metadata";
import {
  occurrenceDraft,
  occurrenceLabel,
  resolveOccurrenceDraft,
} from "@/lib/data/occurrence";
import { mergeAISuggestionNames } from "@/lib/ai/suggestion";
import type { InboxEntry } from "@/lib/data/inbox";
import { entryBodyLimit, entryTitleLimit } from "@/lib/data/inbox-input";
import {
  parseInboxReviewInput,
  type InboxReviewInput,
} from "@/lib/data/inbox-review";
import {
  initialReviewClassification,
  reviewablePresetsForKind,
  wikiItemKindLabel,
  wikiItemSubtypeLabel,
  type ReviewableWikiItemKind,
} from "@/lib/data/wiki-item";
import styles from "@/app/page.module.css";

export function EntryReviewList({
  collectionOptions,
  entries,
  initialEntryID = null,
  tagOptions,
}: {
  collectionOptions: string[];
  entries: InboxEntry[];
  initialEntryID?: string | null;
  tagOptions: string[];
}) {
  const router = useRouter();
  const [selectedEntry, setSelectedEntry] = useState<InboxEntry | null>(
    () => entries.find((entry) => entry.id === initialEntryID) ?? null,
  );
  // Reflect server-confirmed mutations immediately while router refresh is in
  // flight. Rapid reopening must never submit the previous revision again.
  const [savedReviews, setSavedReviews] = useState<
    Record<string, { entry: InboxEntry; done: boolean }>
  >({});

  return (
    <>
      {entries.map((source) => {
        const saved = savedReviews[source.id];
        const latest =
          saved && saved.entry.revision >= source.revision ? saved : null;
        if (latest?.done) return null;
        const entry = latest?.entry ?? source;
        const excerpt = entryExcerpt(entry);

        return (
          <article className={styles.entryCard} key={entry.id}>
            <div className={styles.entryMeta}>
              <time dateTime={entry.occurredAt ?? undefined}>
                {occurrenceLabel(entry)}
              </time>
            </div>
            <h3>{entryTitle(entry)}</h3>
            {excerpt ? <p>{excerpt}</p> : null}
            <footer>
              <div className={styles.tags}>
                <span>Needs review</span>
                {entry.itemKind !== "capture" ? (
                  <>
                    <span>{wikiItemKindLabel(entry.itemKind)}</span>
                    <span>
                      {wikiItemSubtypeLabel(entry.itemKind, entry.itemSubtype)}
                    </span>
                  </>
                ) : null}
                {entry.collectionNames.map((name) => (
                  <span key={`collection:${name.toLocaleLowerCase()}`}>
                    {name}
                  </span>
                ))}
                {entry.tagNames.slice(0, 3).map((name) => (
                  <span key={`tag:${name.toLocaleLowerCase()}`}>#{name}</span>
                ))}
                {entry.tagNames.length > 3 ? (
                  <span>+{entry.tagNames.length - 3}</span>
                ) : null}
              </div>
              <Button
                variant="secondary"

                onClick={() => setSelectedEntry(entry)}
                type="button"
              >
                Organize
                <Icon name="chevron" size={14} />
              </Button>
            </footer>
          </article>
        );
      })}

      {selectedEntry ? (
        <EntryReviewDialog
          entry={selectedEntry}
          key={`${selectedEntry.id}:${selectedEntry.revision}`}
          collectionOptions={collectionOptions}
          onClose={() => {
            setSelectedEntry(null);
            if (initialEntryID) router.replace("/inbox", { scroll: false });
          }}
          onSaved={(entry, done) => {
            setSavedReviews((current) => ({
              ...current,
              [entry.id]: { entry, done },
            }));
            setSelectedEntry(null);
            if (initialEntryID) router.replace("/inbox", { scroll: false });
          }}
          tagOptions={tagOptions}
        />
      ) : null}
    </>
  );
}

export function EntryReviewDialog({
  collectionOptions,
  entry,
  onClose,
  onSaved,
  tagOptions,
  organized = false,
}: {
  collectionOptions: string[];
  entry: InboxEntry;
  onClose: () => void;
  onSaved: (entry: InboxEntry, done: boolean) => void;
  tagOptions: string[];
  organized?: boolean;
}) {
  const router = useRouter();
  const [title, setTitle] = useState(entry.title ?? "");
  const [body, setBody] = useState(entry.body);
  const [bodyRich, setBodyRich] = useState(entry.bodyRich);
  const [collectionNames, setCollectionNames] = useState(entry.collectionNames);
  const [collectionInput, setCollectionInput] = useState("");
  const initialClassification = initialReviewClassification(entry);
  const [itemKind, setItemKind] = useState<ReviewableWikiItemKind>(
    initialClassification.itemKind,
  );
  const [itemSubtype, setItemSubtype] = useState(
    initialClassification.itemSubtype,
  );
  const [occurrence, setOccurrence] = useState(() => occurrenceDraft(entry));
  const [photoPlace, setPhotoPlace] = useState<PhotoPlaceDraft | null>(null);
  const [isPending, setIsPending] = useState(false);
  const [result, setResult] = useState<ReviewInboxEntryResult | null>(null);
  const [tagNames, setTagNames] = useState(entry.tagNames);
  const [tagInput, setTagInput] = useState("");

  useEffect(() => {
    function handleKeyDown(event: KeyboardEvent) {
      if (
        event.key === "Escape" &&
        !(
          event.target instanceof Element &&
          event.target.closest("[data-escape-layer]")
        ) &&
        !isPending
      ) {
        onClose();
      }
    }

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [isPending, onClose]);

  async function submitReview(intent: "done" | "save") {
    const resolved = resolveOccurrenceDraft(occurrence, entry);
    if (resolved.error) {
      setResult({ message: resolved.error, status: "error" });
      return;
    }
    const input: InboxReviewInput = {
      photoPlace,
      ...resolved.value!,
      body,
      bodyRich: bodyRich?.text === body ? bodyRich : null,
      collectionNames: namesIncludingDraft(collectionNames, collectionInput),
      id: entry.id,
      itemKind,
      itemSubtype,
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
      const nextResult = await reviewInboxEntry(parsedInput.data, intent);

      if (nextResult.status === "saved" || nextResult.status === "done") {
        onSaved(
          {
            ...entry,
            ...parsedInput.data,
            datePrecision: parsedInput.data.datePrecision ?? "exact",
            occurredEnd: parsedInput.data.occurredEnd ?? null,
            occurredLabel: parsedInput.data.occurredLabel ?? null,
            revision: nextResult.revision,
          },
          nextResult.status === "done",
        );
        router.refresh();
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
    void submitReview("save");
  }

  return (
    <div
      className={styles.reviewBackdrop}
      onMouseDown={(event) => {
        if (event.currentTarget === event.target && !isPending) {
          onClose();
        }
      }}
    >
      <section
        aria-labelledby="review-heading"
        aria-modal="true"
        className={styles.reviewDialog}
        role="dialog"
      >
        <header className={styles.reviewHeader}>
          <div>
            <p>{organized ? "Life Wiki editor" : "Inbox review"}</p>
            <h2 id="review-heading">
              {organized
                ? `Edit ${wikiItemKindLabel(entry.itemKind)}`
                : "Organize Capture"}
            </h2>
            {organized ? (
              <p>
                This {wikiItemKindLabel(entry.itemKind).toLocaleLowerCase()} is
                already part of your Life Wiki.
              </p>
            ) : (
              <p>
                Keep this as Writing, an Event, or a Story, or use a focused
                form for a structured record.
              </p>
            )}
            <Link href={`/history?entry=${entry.id}`}>Version history</Link>
            <p>
              <Link href={`/explore?entry=${entry.id}`}>Explore with AI</Link> ·
              Uses the saved version. Save your edits first.
            </p>
          </div>
          <button
            aria-label={organized ? "Close item editor" : "Close Inbox review"}
            className={styles.closeReviewButton}
            disabled={isPending}
            onClick={onClose}
            type="button"
          >
            ×
          </button>
        </header>

        <form className={styles.reviewForm} onSubmit={handleSubmit}>
          {!organized && (
            <EntryAISuggestionsPanel
              entryID={entry.id}
              revision={entry.revision}
              disabled={isPending}
              onApply={(key, value) => {
                if (key === "dateText" && typeof value === "string")
                  setOccurrence((current) => ({
                    ...current,
                    precision: "approximate",
                    label: value,
                    start: "",
                    end: "",
                  }));
                if (key === "title" && typeof value === "string")
                  setTitle(value);
                if (
                  key === "classification" &&
                  entry.itemKind === "capture" &&
                  value &&
                  typeof value === "object" &&
                  "itemKind" in value &&
                  "itemSubtype" in value
                ) {
                  setItemKind(value.itemKind);
                  setItemSubtype(value.itemSubtype);
                }
                if (key === "collections" && Array.isArray(value))
                  setCollectionNames((current) =>
                    mergeAISuggestionNames(current, value, 20),
                  );
                if (key === "tags" && Array.isArray(value))
                  setTagNames((current) =>
                    mergeAISuggestionNames(current, value, 50),
                  );
              }}
            />
          )}
          <label>
            <span>
              Title
              {itemKind === "event" && itemSubtype === "first_time" ? (
                <span aria-hidden="true"> *</span>
              ) : null}
            </span>
            <input
              aria-label="Title"
              autoFocus
              disabled={isPending}
              maxLength={entryTitleLimit}
              onChange={(event) => setTitle(event.target.value)}
              placeholder={
                itemKind === "event" && itemSubtype === "first_time"
                  ? "Required for a First Time"
                  : "Add a title"
              }
              required={itemKind === "event" && itemSubtype === "first_time"}
              value={title}
            />
          </label>

          <div className={styles.reviewRichTextField}>
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

          <section
            aria-labelledby="classification-heading"
            className={styles.classificationPanel}
          >
            <div className={styles.classificationHeading}>
              <strong id="classification-heading">
                {entry.itemKind === "capture" ? "Organize as" : "Identity"}
              </strong>
              <span>
                {entry.itemKind === "capture"
                  ? "Choose one durable home in your Life Wiki."
                  : "Kind stays fixed; only a compatible type can change."}
              </span>
            </div>
            <div className={styles.reviewFieldRow}>
              <label>
                <span>Kind</span>
                <select
                  disabled={isPending || entry.itemKind !== "capture"}
                  onChange={(event) => {
                    const nextKind = event.target
                      .value as ReviewableWikiItemKind;
                    setItemKind(nextKind);
                    setItemSubtype(
                      reviewablePresetsForKind(nextKind)[0]?.subtype ?? "note",
                    );
                  }}
                  value={itemKind}
                >
                  <option value="writing">Writing</option>
                  <option value="event">Event</option>
                  <option value="story">Story</option>
                </select>
              </label>
              <label>
                <span>Type</span>
                <select
                  disabled={isPending}
                  onChange={(event) => setItemSubtype(event.target.value)}
                  value={itemSubtype}
                >
                  {reviewablePresetsForKind(itemKind).map((preset) => (
                    <option key={preset.subtype} value={preset.subtype}>
                      {preset.label}
                    </option>
                  ))}
                </select>
              </label>
            </div>
            {entry.itemKind === "capture" ? (
              <div className={styles.specializedHandoffs}>
                <span>Or create a structured record</span>
                <Link href={`/homes?source=${entry.id}`}>
                  <Icon name="home" size={15} />
                  Home
                </Link>
                <Link href={`/vehicles?source=${entry.id}`}>
                  <Icon name="car" size={15} />
                  Vehicle
                </Link>
                <Link href={`/goals?source=${entry.id}`}>
                  <Icon name="target" size={15} />
                  Goal
                </Link>
              </div>
            ) : null}
          </section>
          <EntryPhotoDates
            place={photoPlace}
            onPlaceChange={setPhotoPlace}
            entryId={entry.id}
            disabled={isPending}
            onUseDate={(date) =>
              setOccurrence((current) => photoCalendarDateDraft(date, current))
            }
          />
          <OccurrenceEditor
            value={occurrence}
            onChange={setOccurrence}
            disabled={isPending}
          />

          <EntryOrganizationEditor
            disabled={isPending}
            kind="collection"
            names={collectionNames}
            onChange={setCollectionNames}
            input={collectionInput}
            onInputChange={setCollectionInput}
            options={collectionOptions}
          />

          <EntryOrganizationEditor
            disabled={isPending}
            kind="tag"
            names={tagNames}
            onChange={setTagNames}
            input={tagInput}
            onInputChange={setTagInput}
            options={tagOptions}
          />

          {result ? (
            <p className={styles.reviewError} role="alert">
              {result.message}
            </p>
          ) : null}

          <footer className={styles.reviewActions}>
            <Button
              variant="secondary"

              disabled={isPending}
              onClick={onClose}
              type="button"
            >
              Cancel
            </Button>
            <div>
              <Button
                variant="primary"

                disabled={isPending}
                type="submit"
              >
                Save changes
              </Button>
              {!organized && (
                <Button
                  variant="primary"

                  disabled={isPending}
                  onClick={() => void submitReview("done")}
                  type="button"
                >
                  <Icon name="check" size={16} />
                  {isPending ? "Saving…" : "Save to Library"}
                </Button>
              )}
            </div>
          </footer>
        </form>
      </section>
    </div>
  );
}

function namesIncludingDraft(names: string[], draft: string) {
  const name = draft.trim();
  return name ? [...names, name] : names;
}

function entryTitle(entry: InboxEntry) {
  if (entry.title) {
    return entry.title;
  }

  const body = entry.body.trim();
  const firstLine = body.split(/\r?\n/, 1)[0]?.trim() ?? "";
  return truncate(firstLine || "Untitled capture", 90);
}

function entryExcerpt(entry: InboxEntry) {
  const body = entry.body.trim();

  if (!body) {
    return "";
  }

  if (entry.title) {
    return truncate(body, 280);
  }

  const firstLineEnd = body.indexOf("\n");

  if (firstLineEnd >= 0) {
    return truncate(body.slice(firstLineEnd + 1).trim(), 280);
  }

  return body.length > 90 ? truncate(body.slice(90).trim(), 280) : "";
}

function truncate(value: string, limit: number) {
  return value.length > limit ? `${value.slice(0, limit).trimEnd()}…` : value;
}
