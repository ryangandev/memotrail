"use client";

import { useEffect, useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import {
  reviewInboxEntry,
  type ReviewInboxEntryResult,
} from "@/app/inbox/actions";
import { Icon } from "@/components/icon";
import type { InboxEntry } from "@/lib/data/inbox";
import { entryBodyLimit, entryTitleLimit } from "@/lib/data/inbox-input";
import {
  parseInboxReviewInput,
  type InboxReviewInput,
  type ReviewableEntryType,
} from "@/lib/data/inbox-review";
import styles from "@/app/page.module.css";

export function EntryReviewList({ entries }: { entries: InboxEntry[] }) {
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
          onClose={() => setSelectedEntry(null)}
        />
      ) : null}
    </>
  );
}

function EntryReviewDialog({
  entry,
  onClose,
}: {
  entry: InboxEntry;
  onClose: () => void;
}) {
  const router = useRouter();
  const [title, setTitle] = useState(entry.title ?? "");
  const [body, setBody] = useState(entry.body);
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
      entryType,
      id: entry.id,
      occurredAt: Number.isNaN(localDate.getTime())
        ? occurredAt
        : localDate.toISOString(),
      occurredTimezone,
      revision: entry.revision,
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

          <p className={styles.reviewHint}>
            Collections and tags will be editable in the next organization step.
          </p>

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
