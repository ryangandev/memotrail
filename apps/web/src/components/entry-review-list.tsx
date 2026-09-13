"use client";
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
import { OccurrenceEditor } from "@/components/occurrence-editor";
import { EntryPhotoDates } from "@/components/entry-photo-dates";
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
  type ReviewableEntryType,
} from "@/lib/data/inbox-review";
import styles from "@/app/page.module.css";

export function EntryReviewList({
  collectionOptions,
  entries,
  tagOptions,
}: {
  collectionOptions: string[];
  entries: InboxEntry[];
  tagOptions: string[];
}) {
  const [selectedEntry, setSelectedEntry] = useState<InboxEntry | null>(null);
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
                <span>Unreviewed</span>
                {entry.entryType === "first_time" ? (
                  <span>First Time</span>
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
              <button
                className={styles.reviewEntryButton}
                onClick={() => setSelectedEntry(entry)}
                type="button"
              >
                Review
                <Icon name="chevron" size={14} />
              </button>
            </footer>
          </article>
        );
      })}

      {selectedEntry ? (
        <EntryReviewDialog
          entry={selectedEntry}
          key={`${selectedEntry.id}:${selectedEntry.revision}`}
          collectionOptions={collectionOptions}
          onClose={() => setSelectedEntry(null)}
          onSaved={(entry, done) => {
            setSavedReviews((current) => ({
              ...current,
              [entry.id]: { entry, done },
            }));
            setSelectedEntry(null);
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
  const [collectionNames, setCollectionNames] = useState(entry.collectionNames);
  const [collectionInput, setCollectionInput] = useState("");
  const [entryType, setEntryType] = useState<ReviewableEntryType>(
    entry.entryType,
  );
  const [occurrence, setOccurrence] = useState(() => occurrenceDraft(entry));
  const [photoPlace, setPhotoPlace] = useState<PhotoPlaceDraft | null>(null);
  const [isPending, setIsPending] = useState(false);
  const [result, setResult] = useState<ReviewInboxEntryResult | null>(null);
  const [tagNames, setTagNames] = useState(entry.tagNames);
  const [tagInput, setTagInput] = useState("");

  useEffect(() => {
    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape" && !isPending) {
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
      collectionNames: namesIncludingDraft(collectionNames, collectionInput),
      entryType,
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
            <p>{organized ? "Entry editor" : "Inbox review"}</p>
            <h2 id="review-heading">
              {organized ? "Edit Entry" : "Organize Entry"}
            </h2>
            {organized ? (
              <p>This Entry stays organized when you save.</p>
            ) : null}
            <Link href={`/history?entry=${entry.id}`}>Version history</Link>
            <p>
              <Link href={`/explore?entry=${entry.id}`}>Explore with AI</Link> ·
              Uses the saved version. Save your edits first.
            </p>
          </div>
          <button
            aria-label="Close Entry review"
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
                  key === "entryType" &&
                  (value === "standard" || value === "first_time")
                )
                  setEntryType(value);
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
            <span>Title</span>
            <input
              autoFocus
              disabled={isPending}
              maxLength={entryTitleLimit}
              onChange={(event) => setTitle(event.target.value)}
              placeholder="Optional for a Standard Entry"
              value={title}
            />
          </label>

          <label>
            <span>Note</span>
            <textarea
              disabled={isPending}
              maxLength={entryBodyLimit}
              onChange={(event) => setBody(event.target.value)}
              rows={9}
              value={body}
            />
          </label>

          <div className={styles.reviewFieldRow}>
            <label>
              <span>Type</span>
              <select
                disabled={isPending}
                onChange={(event) =>
                  setEntryType(event.target.value as ReviewableEntryType)
                }
                value={entryType}
              >
                <option value="standard">Standard Entry</option>
                <option value="first_time">First Time</option>
              </select>
            </label>
          </div>
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

          <OrganizationNameEditor
            disabled={isPending}
            label="Collections"
            maximumCount={20}
            maximumNameLength={80}
            names={collectionNames}
            onChange={setCollectionNames}
            input={collectionInput}
            onInputChange={setCollectionInput}
            options={collectionOptions}
            placeholder="Add a Collection"
          />

          <OrganizationNameEditor
            disabled={isPending}
            label="Tags"
            maximumCount={50}
            maximumNameLength={60}
            names={tagNames}
            onChange={setTagNames}
            input={tagInput}
            onInputChange={setTagInput}
            options={tagOptions}
            placeholder="Add a tag"
          />

          {result ? (
            <p className={styles.reviewError} role="alert">
              {result.message}
            </p>
          ) : null}

          <footer className={styles.reviewActions}>
            <button
              className={styles.cancelReviewButton}
              disabled={isPending}
              onClick={onClose}
              type="button"
            >
              Cancel
            </button>
            <div>
              <button
                className={styles.secondaryReviewButton}
                disabled={isPending}
                type="submit"
              >
                Save changes
              </button>
              {!organized && (
                <button
                  className={styles.doneButton}
                  disabled={isPending}
                  onClick={() => void submitReview("done")}
                  type="button"
                >
                  <Icon name="check" size={16} />
                  {isPending ? "Saving…" : "Done"}
                </button>
              )}
            </div>
          </footer>
        </form>
      </section>
    </div>
  );
}

function OrganizationNameEditor({
  disabled,
  label,
  maximumCount,
  maximumNameLength,
  names,
  onChange,
  input,
  onInputChange,
  options,
  placeholder,
}: {
  disabled: boolean;
  label: string;
  maximumCount: number;
  maximumNameLength: number;
  names: string[];
  onChange: (names: string[]) => void;
  input: string;
  onInputChange: (input: string) => void;
  options: string[];
  placeholder: string;
}) {
  const datalistId = `review-${label.toLocaleLowerCase()}-options`;
  const selectedNames = new Set(names.map((name) => name.toLocaleLowerCase()));
  const suggestions = options.filter(
    (option) => !selectedNames.has(option.toLocaleLowerCase()),
  );

  function addName(value: string) {
    const name = value.trim();

    if (
      !name ||
      name.length > maximumNameLength ||
      names.length >= maximumCount ||
      selectedNames.has(name.toLocaleLowerCase())
    ) {
      onInputChange("");
      return;
    }

    onChange([...names, name]);
    onInputChange("");
  }

  return (
    <fieldset className={styles.organizationEditor} disabled={disabled}>
      <legend>{label}</legend>
      {names.length > 0 ? (
        <div className={styles.organizationChips}>
          {names.map((name) => (
            <button
              aria-label={`Remove ${name} from ${label}`}
              key={name.toLocaleLowerCase()}
              onClick={() => onChange(names.filter((item) => item !== name))}
              type="button"
            >
              {name}
              <span aria-hidden="true">×</span>
            </button>
          ))}
        </div>
      ) : null}
      <input
        list={datalistId}
        maxLength={maximumNameLength}
        onChange={(event) => onInputChange(event.target.value)}
        onKeyDown={(event) => {
          if (event.key === "Enter") {
            event.preventDefault();
            addName(input);
          }
        }}
        placeholder={`${placeholder} and press Enter`}
        value={input}
      />
      <datalist id={datalistId}>
        {suggestions.map((suggestion) => (
          <option key={suggestion.toLocaleLowerCase()} value={suggestion} />
        ))}
      </datalist>
      <p>
        {names.length} of {maximumCount}
      </p>
    </fieldset>
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
  return truncate(firstLine || "Untitled Entry", 90);
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
