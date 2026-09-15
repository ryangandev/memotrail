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
  finishInboxCapture,
  syncInboxEntry,
  type SyncInboxEntryResult,
} from "@/app/inbox/actions";
import { Icon } from "@/components/icon";
import { ProgressiveImage } from "@/components/progressive-image";
import {
  clearInboxDraft,
  loadInboxDraft,
  persistInboxDraft,
} from "@/lib/data/inbox-draft";
import { OccurrenceEditor } from "./occurrence-editor";
import {
  occurrenceDraft,
  occurrenceLabel,
  resolveOccurrenceDraft,
  type OccurrenceDraft,
} from "@/lib/data/occurrence";
import { entryBodyLimit, parseInboxEntryValues } from "@/lib/data/inbox-input";
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
  queuedOccurrence,
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
import {
  browserSpeechRecognitionConstructor,
  browserVoiceTranscript,
  mergeVoiceTranscript,
  voiceRecognitionErrorMessage,
  type BrowserSpeechRecognition,
} from "@/lib/data/voice-transcript";
import { createClient } from "@/lib/supabase/client";
import styles from "@/app/page.module.css";

type CaptureFeedback = {
  isError: boolean;
  message: string;
};

type VoiceCaptureState = "checking" | "idle" | "listening" | "stopping";

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
  const [occurrence, setOccurrence] = useState<OccurrenceDraft | null>(null);
  const [isLocalStateReady, setIsLocalStateReady] = useState(false);
  const [hasLocalDraft, setHasLocalDraft] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [isSyncing, setIsSyncing] = useState(false);
  const [feedback, setFeedback] = useState<CaptureFeedback>(idleFeedback);
  const [photos, setPhotos] = useState<InboxPhotoDraft[]>([]);
  const [isPhotoStorageAvailable, setIsPhotoStorageAvailable] = useState(true);
  const [pendingEntries, setPendingEntries] = useState<QueuedInboxEntry[]>([]);
  const [isVoiceSupported, setIsVoiceSupported] = useState<boolean | null>(
    null,
  );
  const [voiceState, setVoiceState] = useState<VoiceCaptureState>("checking");
  const [voiceFeedback, setVoiceFeedback] = useState<CaptureFeedback | null>(
    null,
  );
  const pendingEntriesRef = useRef<QueuedInboxEntry[]>([]);
  const syncInFlightRef = useRef(false);
  const bodyInputRef = useRef<HTMLTextAreaElement>(null);
  const photoInputRef = useRef<HTMLInputElement>(null);
  const voiceRecognitionRef = useRef<BrowserSpeechRecognition | null>(null);
  const voiceBaselineRef = useRef("");
  const voiceHadTranscriptRef = useRef(false);
  const voiceFailedRef = useRef(false);
  const voiceRequestedStopRef = useRef(false);
  const titleRef = useRef("");
  const occurrenceRef = useRef<OccurrenceDraft | null>(null);

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
      if (entry.attachments.length > 0)
        void finishInboxCapture(entry.id).catch(() => undefined);
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
        const savedOccurrence =
          draft?.occurrence ??
          (draft?.occurredAt
            ? occurrenceDraft({
                datePrecision: "exact",
                occurredAt: new Date(draft.occurredAt).toISOString(),
                occurredEnd: null,
                occurredLabel: null,
                occurredTimezone:
                  Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC",
              })
            : null);
        setOccurrence(savedOccurrence);
        titleRef.current = draft?.title ?? "";
        occurrenceRef.current = savedOccurrence;
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

  useEffect(() => {
    let isCanceled = false;

    queueMicrotask(() => {
      if (!isCanceled) {
        setIsVoiceSupported(
          Boolean(browserSpeechRecognitionConstructor(window)),
        );
        setVoiceState("idle");
      }
    });

    return () => {
      isCanceled = true;
      const recognition = voiceRecognitionRef.current;
      if (recognition) {
        recognition.onend = null;
        recognition.onerror = null;
        recognition.onresult = null;
        recognition.abort();
        voiceRecognitionRef.current = null;
      }
    };
  }, []);

  useEffect(() => {
    if (variant === "dialog" && isLocalStateReady) {
      bodyInputRef.current?.focus();
    }
  }, [isLocalStateReady, variant]);

  useEffect(() => {
    const input = bodyInputRef.current;

    if (variant !== "dialog" || !input) {
      return;
    }

    input.style.height = "auto";
    input.style.height = `${input.scrollHeight}px`;
  }, [body, variant]);

  function updateDraft(
    nextTitle: string,
    nextBody: string,
    nextOccurrence: OccurrenceDraft | null,
    preserveVoiceFeedback = false,
  ) {
    titleRef.current = nextTitle;
    occurrenceRef.current = nextOccurrence;
    setTitle(nextTitle);
    setBody(nextBody);
    setOccurrence(nextOccurrence);
    setHasLocalDraft(
      persistInboxDraft(window.localStorage, ownerId, {
        body: nextBody,
        occurredAt: null,
        occurrence: nextOccurrence,
        title: nextTitle,
      }) || photos.length > 0,
    );
    setFeedback(idleFeedback);
    if (!preserveVoiceFeedback) {
      setVoiceFeedback(null);
    }
  }

  function startVoiceCapture() {
    const Recognition = browserSpeechRecognitionConstructor(window);

    if (!Recognition) {
      setIsVoiceSupported(false);
      setVoiceFeedback({
        isError: true,
        message:
          "Voice capture is unavailable in this browser. Text and photo capture still work.",
      });
      return;
    }

    if (voiceRecognitionRef.current || body.length >= entryBodyLimit) {
      if (body.length >= entryBodyLimit) {
        setVoiceFeedback({
          isError: true,
          message: "This note has reached the 50,000 character limit.",
        });
      }
      return;
    }

    const recognition = new Recognition();
    recognition.continuous = true;
    recognition.interimResults = true;
    recognition.lang = navigator.language || "en-US";
    voiceBaselineRef.current = body;
    voiceHadTranscriptRef.current = false;
    voiceFailedRef.current = false;
    voiceRequestedStopRef.current = false;

    recognition.onresult = (event) => {
      const transcript = browserVoiceTranscript(event.results);
      if (!transcript) {
        return;
      }

      voiceHadTranscriptRef.current = true;
      updateDraft(
        titleRef.current,
        mergeVoiceTranscript(voiceBaselineRef.current, transcript),
        occurrenceRef.current,
        true,
      );
    };

    recognition.onerror = (event) => {
      const message = voiceRecognitionErrorMessage(event.error);
      if (!message && voiceRequestedStopRef.current) {
        return;
      }

      voiceFailedRef.current = Boolean(message);
      if (message) {
        setVoiceFeedback({ isError: true, message });
      }
    };

    recognition.onend = () => {
      if (voiceRecognitionRef.current === recognition) {
        voiceRecognitionRef.current = null;
      }
      setVoiceState("idle");

      if (!voiceFailedRef.current) {
        setVoiceFeedback({
          isError: false,
          message: voiceHadTranscriptRef.current
            ? "Transcription added to this draft."
            : "Voice capture stopped before any words were recognized.",
        });
      }
    };

    voiceRecognitionRef.current = recognition;

    try {
      recognition.start();
      setVoiceState("listening");
      setVoiceFeedback({
        isError: false,
        message: "Listening… Tap Stop when done. Audio is not saved.",
      });
    } catch {
      voiceRecognitionRef.current = null;
      setVoiceState("idle");
      setVoiceFeedback({
        isError: true,
        message:
          "Voice capture could not start. Check browser permissions and try again.",
      });
    }
  }

  function stopVoiceCapture() {
    const recognition = voiceRecognitionRef.current;
    if (!recognition) {
      return;
    }

    voiceRequestedStopRef.current = true;
    setVoiceState("stopping");
    setVoiceFeedback({
      isError: false,
      message: "Finishing transcription… Audio was not saved.",
    });
    recognition.stop();
  }

  function toggleRelevantDate() {
    updateDraft(
      title,
      body,
      occurrence
        ? null
        : occurrenceDraft({
            datePrecision: "exact",
            occurredAt: new Date().toISOString(),
            occurredEnd: null,
            occurredLabel: null,
            occurredTimezone:
              Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC",
          }),
    );
  }

  async function handlePhotoSelection(event: ChangeEvent<HTMLInputElement>) {
    setVoiceFeedback(null);
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
      setVoiceFeedback(null);
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
    const parsedDate = occurrence
      ? resolveOccurrenceDraft(occurrence)
      : {
          value: {
            occurredAt: now.toISOString(),
            occurredEnd: null,
            occurredLabel: null,
            occurredTimezone:
              Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC",
            datePrecision: "exact" as const,
          },
        };

    if (parsedDate.error) {
      setFeedback({ isError: true, message: parsedDate.error });
      return;
    }

    setIsSaving(true);
    const queuedAt = now.toISOString();
    const entry: QueuedInboxEntry = {
      attachments: photos.map(queuedInboxAttachment),
      body: parsedInput.data.body,
      id: crypto.randomUUID(),
      ...parsedDate.value!,
      queuedAt,
      title: parsedInput.data.title,
      version: 3,
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
    setOccurrence(null);
    titleRef.current = "";
    occurrenceRef.current = null;
    setPhotos([]);
    setHasLocalDraft(false);
    setVoiceFeedback(null);
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
          {variant === "page" ? (
            <span className={styles.captureSpark} aria-hidden="true">
              <Icon name="sparkle" size={19} />
            </span>
          ) : null}
          <div className={styles.captureFields}>
            <label
              className={styles.visuallyHidden}
              htmlFor={`${idPrefix}-body`}
            >
              Entry text
            </label>
            <textarea
              className={styles.captureBody}
              disabled={isSaving || !isLocalStateReady || voiceState !== "idle"}
              id={`${idPrefix}-body`}
              maxLength={entryBodyLimit}
              name="body"
              onChange={(event) =>
                updateDraft(title, event.target.value, occurrence)
              }
              placeholder="What is on your mind?"
              ref={bodyInputRef}
              rows={variant === "dialog" ? 1 : 4}
              value={body}
            />
          </div>
        </div>
        {occurrence ? (
          <div
            className={`${styles.reviewForm} ${styles.captureOccurrencePanel}`}
          >
            <OccurrenceEditor
              value={occurrence}
              onChange={(value) => updateDraft(title, body, value)}
              disabled={isSaving || !isLocalStateReady || voiceState !== "idle"}
            />
            <button
              className={styles.removeCaptureDateButton}
              disabled={isSaving || !isLocalStateReady || voiceState !== "idle"}
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
        {voiceFeedback ? (
          <p
            aria-live="polite"
            className={`${styles.captureVoiceStatus} ${voiceFeedback.isError ? styles.captureVoiceError : ""}`}
            role={voiceFeedback.isError ? "alert" : "status"}
          >
            <Icon name={voiceFeedback.isError ? "mic" : "sparkle"} size={15} />
            {voiceFeedback.message}
          </p>
        ) : null}
        <div className={styles.captureActions}>
          <div>
            <button
              aria-pressed={Boolean(occurrence)}
              className={`${styles.quietButton} ${occurrence ? styles.activeQuietButton : ""}`}
              disabled={isSaving || !isLocalStateReady || voiceState !== "idle"}
              onClick={toggleRelevantDate}
              type="button"
            >
              <Icon name="calendar" />
              <span>{occurrence ? "Custom date" : "Date"}</span>
            </button>
            <button
              aria-label={
                voiceState === "listening"
                  ? "Stop voice capture"
                  : isVoiceSupported === false
                    ? "Voice capture unavailable in this browser"
                    : "Start voice capture"
              }
              aria-pressed={voiceState === "listening"}
              className={`${styles.quietButton} ${voiceState === "listening" ? styles.listeningQuietButton : ""}`}
              disabled={
                isSaving ||
                !isLocalStateReady ||
                voiceState === "checking" ||
                voiceState === "stopping"
              }
              onClick={
                voiceState === "listening"
                  ? stopVoiceCapture
                  : startVoiceCapture
              }
              title={
                isVoiceSupported === false
                  ? "Voice capture is unavailable in this browser"
                  : undefined
              }
              type="button"
            >
              <Icon name={voiceState === "listening" ? "stop" : "mic"} />
              {voiceState === "listening" ? "Stop" : "Voice"}
            </button>
            <button
              aria-label="Add photos"
              aria-pressed={photos.length > 0}
              className={`${styles.quietButton} ${photos.length > 0 ? styles.activeQuietButton : ""}`}
              disabled={
                isSaving ||
                !isLocalStateReady ||
                !isPhotoStorageAvailable ||
                voiceState !== "idle"
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
                isSaving ||
                !isLocalStateReady ||
                !isPhotoStorageAvailable ||
                voiceState !== "idle"
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
              disabled={
                isSaving ||
                isSyncing ||
                !isLocalStateReady ||
                voiceState !== "idle"
              }
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
                  <time dateTime={entry.occurredAt ?? undefined}>
                    {occurrenceLabel(queuedOccurrence(entry))}
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
      <ProgressiveImage alt={`Selected ${photo.file.name}`} src={previewUrl} />
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

    await client.storage.from("entry-media").upload(objectPath, photo.file, {
      cacheControl: "3600",
      contentType: attachment.mimeType,
      upsert: false,
    });

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
