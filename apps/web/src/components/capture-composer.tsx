"use client";

import {
  type ChangeEvent,
  useCallback,
  useEffect,
  useRef,
  useState,
  type FormEvent,
} from "react";
import { useRouter } from "next/navigation";
import {
  registerEntryAttachment,
  syncInboxEntry,
  type SyncInboxEntryResult,
} from "@/app/inbox/actions";
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
  createFirstTimeObjectPath,
  type FirstTimeAttachmentInput,
} from "@/lib/data/first-time-input";
import {
  enqueueInboxEntry,
  inboxQueueChangedEvent,
  loadInboxQueue,
  removeInboxQueueEntry,
  type QueuedInboxEntry,
} from "@/lib/data/inbox-queue";
import {
  queuedInboxAttachment,
  validateInboxPhotoFiles,
  type InboxPhotoDraft,
} from "@/lib/data/inbox-photo";
import {
  loadInboxPhotoDrafts,
  persistInboxPhotoDrafts,
  removeInboxPhotoDrafts,
} from "@/lib/data/inbox-photo-store";
import { createClient } from "@/lib/supabase/client";
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
  const [photos, setPhotos] = useState<InboxPhotoDraft[]>([]);
  const [isPhotoStorageAvailable, setIsPhotoStorageAvailable] = useState(true);
  const [pendingEntries, setPendingEntries] = useState<QueuedInboxEntry[]>([]);
  const pendingEntriesRef = useRef<QueuedInboxEntry[]>([]);
  const syncInFlightRef = useRef(false);
  const photoInputRef = useRef<HTMLInputElement>(null);

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

      if (entry.attachments.length > 0) {
        try {
          latestResult = await synchronizeAttachments(ownerId, entry);
        } catch {
          latestResult = {
            message:
              "Photos are saved on this device. MemoTrail will retry when you are online.",
            status: "retry",
          };
        }

        if (latestResult.status === "retry") {
          break;
        }
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
      void (async () => {
        let storedPhotos: InboxPhotoDraft[] = [];

        try {
          storedPhotos = await loadInboxPhotoDrafts(ownerId);
        } catch {
          setIsPhotoStorageAvailable(false);
          setFeedback({
            isError: true,
            message:
              "Photo drafts are unavailable in this browser. Text capture still works.",
          });
        }

        if (isCanceled) {
          return;
        }

        const queuedPhotoIds = new Set(
          queue.flatMap((entry) =>
            entry.attachments.map((attachment) => attachment.id),
          ),
        );
        const draftPhotos = storedPhotos.filter(
          (photo) => !queuedPhotoIds.has(photo.id),
        );

        setTitle(draft?.title ?? "");
        setBody(draft?.body ?? "");
        setOccurredAt(draft?.occurredAt ?? null);
        setPhotos(draftPhotos);
        setHasLocalDraft(Boolean(draft) || draftPhotos.length > 0);
        replacePendingEntries(queue);
        setIsLocalStateReady(true);

        if (queue.length > 0 && navigator.onLine) {
          void synchronizeQueue();
        }
      })();
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
      }) || photos.length > 0,
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

  async function handlePhotoSelection(event: ChangeEvent<HTMLInputElement>) {
    const selection = validateInboxPhotoFiles(
      Array.from(event.target.files ?? []),
      photos.length,
    );
    event.target.value = "";

    if (selection.accepted.length === 0) {
      if (selection.message) {
        setFeedback({ isError: true, message: selection.message });
      }
      return;
    }

    try {
      await persistInboxPhotoDrafts(ownerId, selection.accepted);
      setPhotos((current) => [...current, ...selection.accepted]);
      setHasLocalDraft(true);
      setFeedback({
        isError: Boolean(selection.message),
        message: selection.message ?? "Photos saved in this draft.",
      });
    } catch {
      setIsPhotoStorageAvailable(false);
      setFeedback({
        isError: true,
        message:
          "This browser could not keep those photos safely. Try another browser or device.",
      });
    }
  }

  async function removePhoto(photoId: string) {
    try {
      await removeInboxPhotoDrafts(ownerId, [photoId]);
      const nextPhotos = photos.filter((photo) => photo.id !== photoId);
      setPhotos(nextPhotos);
      setHasLocalDraft(
        Boolean(loadInboxDraft(window.localStorage, ownerId)) ||
          nextPhotos.length > 0,
      );
      setFeedback(idleFeedback);
    } catch {
      setFeedback({
        isError: true,
        message: "MemoTrail could not remove that local photo. Try again.",
      });
    }
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const parsedInput = parseInboxEntryValues({
      body,
      hasAttachments: photos.length > 0,
      title,
    });

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
      attachments: photos.map(queuedInboxAttachment),
      body: parsedInput.data.body,
      id: crypto.randomUUID(),
      occurredAt: parsedDate.occurredAt,
      occurredTimezone:
        Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC",
      queuedAt,
      title: parsedInput.data.title,
      version: 2,
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
    setPhotos([]);
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

  const composerFeedback = feedback.isError
    ? feedback
    : hasLocalDraft
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
        {photos.length > 0 ? (
          <div className={styles.capturePhotoStrip} aria-label="Draft photos">
            {photos.map((photo) => (
              <CapturePhoto
                key={photo.id}
                photo={photo}
                onRemove={() => void removePhoto(photo.id)}
              />
            ))}
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
              aria-label="Add photos"
              aria-pressed={photos.length > 0}
              className={`${styles.quietButton} ${photos.length > 0 ? styles.activeQuietButton : ""}`}
              disabled={
                isSaving || !isLocalStateReady || !isPhotoStorageAvailable
              }
              onClick={() => photoInputRef.current?.click()}
              type="button"
            >
              <Icon name="photo" />
              <span>
                {photos.length > 0 ? `Photo · ${photos.length}` : "Photo"}
              </span>
            </button>
            <input
              accept="image/jpeg,image/png,image/webp,image/heic,image/heif"
              className={styles.visuallyHidden}
              disabled={
                isSaving || !isLocalStateReady || !isPhotoStorageAvailable
              }
              multiple
              onChange={(event) => void handlePhotoSelection(event)}
              ref={photoInputRef}
              type="file"
            />
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
                {entry.attachments.length > 0 ? (
                  <span className={styles.pendingPhotoCount}>
                    <Icon name="photo" size={14} />
                    {photoCountLabel(entry.attachments.length)}
                  </span>
                ) : null}
              </article>
            ))}
          </div>
        </section>
      ) : null}
    </>
  );
}

function CapturePhoto({
  onRemove,
  photo,
}: {
  onRemove: () => void;
  photo: InboxPhotoDraft;
}) {
  const [previewUrl] = useState(() => URL.createObjectURL(photo.file));

  useEffect(() => {
    return () => URL.revokeObjectURL(previewUrl);
  }, [previewUrl]);

  return (
    <div className={styles.capturePhoto}>
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img alt={`Selected ${photo.file.name}`} src={previewUrl} />
      <button
        aria-label={`Remove selected ${photo.file.name}`}
        onClick={onRemove}
        type="button"
      >
        ×
      </button>
    </div>
  );
}

async function synchronizeAttachments(
  ownerId: string,
  entry: QueuedInboxEntry,
): Promise<SyncInboxEntryResult> {
  const storedPhotos = await loadInboxPhotoDrafts(ownerId);
  const photosById = new Map(storedPhotos.map((photo) => [photo.id, photo]));
  const client = createClient();

  for (const attachment of entry.attachments) {
    const photo = photosById.get(attachment.id);
    const objectPath = createFirstTimeObjectPath(
      ownerId,
      entry.id,
      attachment.id,
      attachment.mimeType,
    );

    if (!objectPath) {
      return {
        message:
          "A pending photo reference is invalid and needs your attention.",
        status: "retry",
      };
    }

    const attachmentInput: FirstTimeAttachmentInput = {
      attachmentId: attachment.id,
      byteSize: attachment.size,
      entryId: entry.id,
      mimeType: attachment.mimeType,
      objectPath,
      originalFilename: attachment.name || null,
      pixelHeight: null,
      pixelWidth: null,
    };

    if (!photo) {
      const registered = await registerEntryAttachment(attachmentInput);

      if (registered.status === "synced") {
        continue;
      }

      return {
        message:
          "A pending photo is missing from this device. Keep this page open and select the photo again if needed.",
        status: "retry",
      };
    }

    if (
      photo.file.name !== attachment.name ||
      photo.file.size !== attachment.size ||
      photo.file.lastModified !== attachment.lastModified ||
      photo.mimeType !== attachment.mimeType
    ) {
      return {
        message: "A pending photo changed on this device and cannot be synced.",
        status: "retry",
      };
    }

    const upload = await client.storage
      .from("entry-media")
      .upload(objectPath, photo.file, {
        cacheControl: "3600",
        contentType: attachment.mimeType,
        upsert: true,
      });

    if (upload.error) {
      return {
        message:
          "Photos are saved on this device. MemoTrail will retry when you are online.",
        status: "retry",
      };
    }

    const registered = await registerEntryAttachment(attachmentInput);

    if (registered.status === "retry") {
      return registered;
    }

    try {
      await removeInboxPhotoDrafts(ownerId, [attachment.id]);
    } catch {
      return {
        message:
          "This photo reached MemoTrail, but its local pending copy could not be cleared. Retry to finish.",
        status: "retry",
      };
    }
  }

  return {
    message: `Saved to Inbox with ${photoCountLabel(entry.attachments.length)}.`,
    status: "synced",
  };
}

function pendingCountLabel(count: number) {
  return count === 1 ? "1 Entry" : `${count} Entries`;
}

function photoCountLabel(count: number) {
  return count === 1 ? "1 photo" : `${count} photos`;
}

function pendingDateLabel(date: string) {
  return new Intl.DateTimeFormat("en", {
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
    month: "short",
  }).format(new Date(date));
}
