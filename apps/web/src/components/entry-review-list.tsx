"use client";

import { useEffect, useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import {
  reviewInboxEntry,
  type ReviewInboxEntryResult,
} from "@/app/inbox/actions";
import { Icon } from "@/components/icon";
import { EntryAISuggestionsPanel } from "@/components/entry-ai-suggestions";
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

  return (
    <>
      {entries.map((entry) => {
        const excerpt = entryExcerpt(entry);

        return (
          <article className={styles.entryCard} key={entry.id}>
            <div className={styles.entryMeta}>
              <time dateTime={entry.occurredAt}>
                {entryDateLabel(entry.occurredAt)}
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
          tagOptions={tagOptions}
        />
      ) : null}
    </>
  );
}

function EntryReviewDialog({
  collectionOptions,
  entry,
  onClose,
  tagOptions,
}: {
  collectionOptions: string[];
  entry: InboxEntry;
  onClose: () => void;
  tagOptions: string[];
}) {
  const router = useRouter();
  const [title, setTitle] = useState(entry.title ?? "");
  const [body, setBody] = useState(entry.body);
  const [collectionNames, setCollectionNames] = useState(entry.collectionNames);
  const [collectionInput, setCollectionInput] = useState("");
  const [entryType, setEntryType] = useState<ReviewableEntryType>(
    entry.entryType,
  );
  const [occurredAt, setOccurredAt] = useState(
    localDateTimeValue(entry.occurredAt),
  );
  const [occurredTimezone, setOccurredTimezone] = useState(
    entry.occurredTimezone ?? localTimezone(),
  );
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
    const localDate = new Date(occurredAt);
    const input: InboxReviewInput = {
      body,
      collectionNames: namesIncludingDraft(collectionNames, collectionInput),
      entryType,
      id: entry.id,
      occurredAt: Number.isNaN(localDate.getTime())
        ? occurredAt
        : localDate.toISOString(),
      occurredTimezone,
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
        router.refresh();
        onClose();
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
            <p>Inbox review</p>
            <h2 id="review-heading">Organize Entry</h2>
            <Link href={`/history?entry=${entry.id}`}>Version history</Link>
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
          <EntryAISuggestionsPanel
            entryID={entry.id}
            revision={entry.revision}
            disabled={isPending}
            onApply={(key, value) => {
              if (key === "title" && typeof value === "string") setTitle(value);
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

            <label>
              <span>Occurred</span>
              <input
                disabled={isPending}
                onChange={(event) => {
                  setOccurredAt(event.target.value);
                  setOccurredTimezone(localTimezone());
                }}
                type="datetime-local"
                value={occurredAt}
              />
            </label>
          </div>

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
              <button
                className={styles.doneButton}
                disabled={isPending}
                onClick={() => void submitReview("done")}
                type="button"
              >
                <Icon name="check" size={16} />
                {isPending ? "Saving…" : "Done"}
              </button>
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

function localDateTimeValue(value: string) {
  const date = new Date(value);
  const localDate = new Date(
    date.getTime() - date.getTimezoneOffset() * 60_000,
  );
  return localDate.toISOString().slice(0, 16);
}

function localTimezone() {
  return Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
}

function entryDateLabel(value: string) {
  return new Intl.DateTimeFormat("en-US", {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(new Date(value));
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
