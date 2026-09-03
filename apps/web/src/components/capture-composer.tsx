"use client";

import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type FormEvent,
} from "react";
import { useRouter } from "next/navigation";
import { syncInboxEntry, type SyncInboxEntryResult } from "@/app/inbox/actions";
import { Icon } from "@/components/icon";
import {
  clearInboxDraft,
  loadInboxDraft,
  persistInboxDraft,
} from "@/lib/data/inbox-draft";
import {
  captureDateLabel,
  localCaptureDateValue,
  parseCaptureDate,
} from "@/lib/data/inbox-capture-date";
import {
  entryBodyLimit,
  entryTitleLimit,
  parseInboxEntryValues,
} from "@/lib/data/inbox-input";
import {
  enqueueInboxEntry,
  inboxQueueChangedEvent,
  loadInboxQueue,
  removeInboxQueueEntry,
  type QueuedInboxEntry,
} from "@/lib/data/inbox-queue";
import styles from "@/app/page.module.css";

type CaptureFeedback = {
  isError: boolean;
  message: string;
};

const idleFeedback: CaptureFeedback = { isError: false, message: "" };

export function CaptureComposer({
  idPrefix = "capture",
  ownerId,
  variant = "page",
}: {
  idPrefix?: string;
  ownerId: string;
  variant?: "dialog" | "page";
}) {
  const router = useRouter();
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [occurredAt, setOccurredAt] = useState<string | null>(null);
  const [isLocalStateReady, setIsLocalStateReady] = useState(false);
  const [hasLocalDraft, setHasLocalDraft] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [isSyncing, setIsSyncing] = useState(false);
  const [feedback, setFeedback] = useState<CaptureFeedback>(idleFeedback);
  const [pendingEntries, setPendingEntries] = useState<QueuedInboxEntry[]>([]);
  const pendingEntriesRef = useRef<QueuedInboxEntry[]>([]);
  const syncInFlightRef = useRef(false);

  const replacePendingEntries = useCallback(
    (entries: QueuedInboxEntry[]) => {
      pendingEntriesRef.current = entries;
      setPendingEntries(entries);
      window.dispatchEvent(
        new CustomEvent(inboxQueueChangedEvent, {
          detail: { count: entries.length, ownerId },
        }),
      );
    },
    [ownerId],
  );

  const synchronizeQueue = useCallback(async () => {
    if (syncInFlightRef.current || pendingEntriesRef.current.length === 0) {
      return;
    }

    syncInFlightRef.current = true;
    setIsSyncing(true);
    let latestResult: SyncInboxEntryResult | null = null;
    let didSyncEntry = false;

    for (const entry of [...pendingEntriesRef.current]) {
      try {
        latestResult = await syncInboxEntry(entry);
      } catch {
        latestResult = {
          message:
            "Saved on this device. MemoTrail will retry when you are online.",
          status: "retry",
        };
      }

      if (latestResult.status === "retry") {
        break;
      }

      const nextQueue = removeInboxQueueEntry(
        window.localStorage,
        ownerId,
        entry.id,
      );

      if (nextQueue === null) {
        latestResult = {
          message:
            "This Entry reached MemoTrail, but its local pending copy could not be cleared.",
          status: "retry",
        };
        break;
      }

      didSyncEntry = true;
      replacePendingEntries(nextQueue);
    }

    syncInFlightRef.current = false;
    setIsSyncing(false);

    if (latestResult) {
      setFeedback({
        isError: latestResult.status === "retry",
        message: latestResult.message,
      });
    }

    if (didSyncEntry) {
      router.refresh();
    }
  }, [ownerId, replacePendingEntries, router]);

  useEffect(() => {
    const draft = loadInboxDraft(window.localStorage, ownerId);
    const queue = loadInboxQueue(window.localStorage, ownerId);
    let isCanceled = false;

    queueMicrotask(() => {
      if (isCanceled) {
        return;
      }

      setTitle(draft?.title ?? "");
      setBody(draft?.body ?? "");
      setOccurredAt(draft?.occurredAt ?? null);
      setHasLocalDraft(Boolean(draft));
      replacePendingEntries(queue);
      setIsLocalStateReady(true);

      if (queue.length > 0 && navigator.onLine) {
        void synchronizeQueue();
      }
    });

    function handleOnline() {
      void synchronizeQueue();
    }

    window.addEventListener("online", handleOnline);

    return () => {
      isCanceled = true;
      window.removeEventListener("online", handleOnline);
    };
  }, [ownerId, replacePendingEntries, synchronizeQueue]);

  function updateDraft(
    nextTitle: string,
    nextBody: string,
    nextOccurredAt: string | null,
  ) {
    setTitle(nextTitle);
    setBody(nextBody);
    setOccurredAt(nextOccurredAt);
    setHasLocalDraft(
      persistInboxDraft(window.localStorage, ownerId, {
        body: nextBody,
        occurredAt: nextOccurredAt,
        title: nextTitle,
      }),
    );
    setFeedback(idleFeedback);
  }

  function toggleRelevantDate() {
    updateDraft(
      title,
      body,
      occurredAt ? null : localCaptureDateValue(new Date()),
    );
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const parsedInput = parseInboxEntryValues({ body, title });

    if (!parsedInput.success) {
      setFeedback({ isError: true, message: parsedInput.message });
      return;
    }

    const now = new Date();
    const parsedDate = parseCaptureDate(occurredAt, now);

    if (!parsedDate.success) {
      setFeedback({ isError: true, message: parsedDate.message });
      return;
    }

    setIsSaving(true);
    const queuedAt = now.toISOString();
    const entry: QueuedInboxEntry = {
      body: parsedInput.data.body,
      id: crypto.randomUUID(),
      occurredAt: parsedDate.occurredAt,
      occurredTimezone:
        Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC",
      queuedAt,
      title: parsedInput.data.title,
      version: 1,
    };
    const nextQueue = enqueueInboxEntry(window.localStorage, ownerId, entry);

    if (!nextQueue) {
      setFeedback({
        isError: true,
        message:
          "MemoTrail could not store this Entry on this device. Your draft is still here.",
      });
      setIsSaving(false);
      return;
    }

    replacePendingEntries(nextQueue);
    clearInboxDraft(window.localStorage, ownerId);
    setTitle("");
    setBody("");
    setOccurredAt(null);
    setHasLocalDraft(false);
    setFeedback({
      isError: false,
      message: navigator.onLine
        ? "Saved on this device. Syncing…"
        : "Saved on this device. Waiting for a connection.",
    });
    setIsSaving(false);
    await synchronizeQueue();
  }

  const composerFeedback = hasLocalDraft
    ? { isError: false, message: "Draft saved on this device." }
    : feedback;

  return (
    <>
      <form
        className={`${styles.captureCard} ${variant === "dialog" ? styles.dialogCaptureCard : ""}`}
        aria-label="Quick capture"
        onSubmit={handleSubmit}
      >
        <div className={styles.captureIntro}>
          <span className={styles.captureSpark} aria-hidden="true">
            <Icon name="sparkle" size={19} />
          </span>
          <div className={styles.captureFields}>
            <label
              className={styles.visuallyHidden}
              htmlFor={`${idPrefix}-title`}
            >
              Entry title
            </label>
            <input
              autoComplete="off"
              className={styles.captureTitle}
              disabled={isSaving || !isLocalStateReady}
              id={`${idPrefix}-title`}
              maxLength={entryTitleLimit}
              name="title"
              onChange={(event) =>
                updateDraft(event.target.value, body, occurredAt)
              }
              placeholder="What is worth keeping?"
              value={title}
            />
            <label
              className={styles.visuallyHidden}
              htmlFor={`${idPrefix}-body`}
            >
              Entry text
            </label>
            <textarea
              className={styles.captureBody}
              disabled={isSaving || !isLocalStateReady}
              id={`${idPrefix}-body`}
              maxLength={entryBodyLimit}
              name="body"
              onChange={(event) =>
                updateDraft(title, event.target.value, occurredAt)
              }
              placeholder="A thought, a first, something learned, or whatever is on your mind."
              rows={4}
              value={body}
            />
          </div>
        </div>
        {occurredAt ? (
          <div className={styles.captureDatePanel}>
            <label htmlFor={`${idPrefix}-occurred-at`}>
              <span>Relevant date and time</span>
              <input
                disabled={isSaving || !isLocalStateReady}
                id={`${idPrefix}-occurred-at`}
                onChange={(event) =>
                  updateDraft(title, body, event.target.value || null)
                }
                type="datetime-local"
                value={occurredAt}
              />
            </label>
            <button
              className={styles.removeCaptureDateButton}
              disabled={isSaving || !isLocalStateReady}
              onClick={() => updateDraft(title, body, null)}
              type="button"
            >
              Use capture time
            </button>
          </div>
        ) : null}
        <div className={styles.captureActions}>
          <div>
            <button
              aria-pressed={Boolean(occurredAt)}
              className={`${styles.quietButton} ${occurredAt ? styles.activeQuietButton : ""}`}
              disabled={isSaving || !isLocalStateReady}
              onClick={toggleRelevantDate}
              type="button"
            >
              <Icon name="calendar" />
              <span>{occurredAt ? captureDateLabel(occurredAt) : "Date"}</span>
            </button>
            <button
              aria-label="Voice capture is coming next"
              className={styles.quietButton}
              disabled
              type="button"
            >
              <Icon name="mic" /> Voice
            </button>
            <button
              aria-label="Photo capture is coming next"
              className={styles.quietButton}
              disabled
              type="button"
            >
              <Icon name="photo" /> Photo
            </button>
          </div>
          <div className={styles.captureSubmitGroup}>
            <p
              className={
                composerFeedback.isError
                  ? styles.captureError
                  : styles.captureStatus
              }
              aria-live="polite"
            >
              {composerFeedback.message}
            </p>
            <button
              className={styles.saveButton}
              disabled={isSaving || isSyncing || !isLocalStateReady}
              type="submit"
            >
              {isSaving ? "Saving…" : "Save to Inbox"}
              <Icon name="chevron" size={16} />
            </button>
          </div>
        </div>
      </form>

      {pendingEntries.length > 0 ? (
        <section
          className={styles.pendingSection}
          aria-labelledby={`${idPrefix}-pending-heading`}
        >
          <div className={styles.sectionHeader}>
            <div>
              <h2 id={`${idPrefix}-pending-heading`}>Pending sync</h2>
              <span>{pendingCountLabel(pendingEntries.length)}</span>
            </div>
            <button
              className={styles.retryButton}
              disabled={isSyncing}
              onClick={() => void synchronizeQueue()}
              type="button"
            >
              <Icon name="refresh" size={14} />
              {isSyncing ? "Syncing…" : "Retry now"}
            </button>
          </div>
          <div className={styles.entryList}>
            {pendingEntries.map((entry) => (
              <article className={styles.pendingEntryCard} key={entry.id}>
                <div className={styles.entryMeta}>
                  <time dateTime={entry.occurredAt}>
                    {pendingDateLabel(entry.occurredAt)}
                  </time>
                  <span className={styles.pendingBadge}>On this device</span>
                </div>
                <h3>{entry.title ?? "Untitled Entry"}</h3>
                {entry.body ? <p>{entry.body}</p> : null}
              </article>
            ))}
          </div>
        </section>
      ) : null}
    </>
  );
}

function pendingCountLabel(count: number) {
  return count === 1 ? "1 Entry" : `${count} Entries`;
}

function pendingDateLabel(date: string) {
  return new Intl.DateTimeFormat("en", {
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
    month: "short",
  }).format(new Date(date));
}
