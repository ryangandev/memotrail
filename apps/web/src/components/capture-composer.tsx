"use client";
import captureComposerStyles from "@/components/capture-composer.module.css";
import entryFormStyles from "@/components/entry-form.module.css";
import entryListStyles from "@/components/entry-list.module.css";
import { Button } from "@/components/button";
import { notify } from "@/components/app-toast";

import {
  type ChangeEvent,
  useCallback,
  useEffect,
  useLayoutEffect,
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
import { Badge } from "@/components/badge";
import { PhotoUploadProgress } from "@/components/photo-upload-progress";
import { RichTextEditor } from "@/components/rich-text-editor";
import { SelectedPhotoPreview } from "@/components/selected-photo-preview";
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
import type { EntryRichText } from "@/lib/data/rich-text";
import type { PhotoUploadProgress as PhotoUploadProgressValue } from "@/lib/media/upload";

type CaptureFeedback = {
  isError: boolean;
  message: string;
};

type VoiceCaptureState = "checking" | "idle" | "listening" | "stopping";

export type NativePhotoPickerState = "canceled" | "opened" | "selected";

const idleFeedback: CaptureFeedback = { isError: false, message: "" };

export function CaptureComposer({
  active = true,
  embedded = false,
  idPrefix = "capture",
  onNativePhotoPickerChange,
  ownerId,
  variant = "page",
}: {
  active?: boolean;
  embedded?: boolean;
  idPrefix?: string;
  onNativePhotoPickerChange?: (state: NativePhotoPickerState) => void;
  ownerId: string;
  variant?: "dialog" | "page";
}) {
  const router = useRouter();
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [bodyRich, setBodyRich] = useState<EntryRichText | null>(null);
  const [occurrence, setOccurrence] = useState<OccurrenceDraft | null>(null);
  const [isLocalStateReady, setIsLocalStateReady] = useState(false);
  const [hasLocalDraft, setHasLocalDraft] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [isSyncing, setIsSyncing] = useState(false);
  const [photoUploadProgress, setPhotoUploadProgress] =
    useState<PhotoUploadProgressValue | null>(null);
  const [feedback, setFeedback] = useState<CaptureFeedback>(idleFeedback);
  const [photos, setPhotos] = useState<InboxPhotoDraft[]>([]);
  const [isPhotoStateReady, setIsPhotoStateReady] = useState(false);
  const [isPhotoStorageAvailable, setIsPhotoStorageAvailable] = useState(true);
  const [pendingEntries, setPendingEntries] = useState<QueuedInboxEntry[]>([]);
  const [showPendingEntries, setShowPendingEntries] = useState(false);
  const [isVoiceSupported, setIsVoiceSupported] = useState<boolean | null>(
    null,
  );
  const [voiceState, setVoiceState] = useState<VoiceCaptureState>("checking");
  const [voiceFeedback, setVoiceFeedback] = useState<CaptureFeedback | null>(
    null,
  );
  const pendingEntriesRef = useRef<QueuedInboxEntry[]>([]);
  const syncInFlightRef = useRef(false);
  const photoInputRef = useRef<HTMLInputElement>(null);
  const submitButtonRef = useRef<HTMLButtonElement>(null);
  const voiceRecognitionRef = useRef<BrowserSpeechRecognition | null>(null);
  const voiceBaselineRef = useRef("");
  const voiceHadTranscriptRef = useRef(false);
  const voiceFailedRef = useRef(false);
  const voiceRequestedStopRef = useRef(false);
  const titleRef = useRef("");
  const occurrenceRef = useRef<OccurrenceDraft | null>(null);

  useEffect(() => {
    const input = photoInputRef.current;
    if (!input || !onNativePhotoPickerChange) return;

    function handlePhotoPickerCancel() {
      onNativePhotoPickerChange?.("canceled");
    }

    input.addEventListener("cancel", handlePhotoPickerCancel);
    return () => input.removeEventListener("cancel", handlePhotoPickerCancel);
  }, [onNativePhotoPickerChange]);

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
        const { bodyRich: queuedBodyRich, ...syncInput } = entry;
        latestResult = await syncInboxEntry(
          syncInput,
          queuedBodyRich ? JSON.stringify(queuedBodyRich) : null,
        );
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
          latestResult = await synchronizeAttachments(
            ownerId,
            entry,
            setPhotoUploadProgress,
          );
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
    setPhotoUploadProgress(null);
    setIsSyncing(false);
    setShowPendingEntries(pendingEntriesRef.current.length > 0);

    if (latestResult?.status === "synced") {
      setFeedback(idleFeedback);
      notify.success(latestResult.message);
    } else if (latestResult) {
      setFeedback({ isError: true, message: latestResult.message });
    }

    if (didSyncEntry) {
      router.refresh();
    }
  }, [ownerId, replacePendingEntries, router]);

  useLayoutEffect(() => {
    if (!active) return;
    const draft = loadInboxDraft(window.localStorage, ownerId);
    const queue = loadInboxQueue(window.localStorage, ownerId);
    let isCanceled = false;

    queueMicrotask(() => {
      if (isCanceled) return;

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

      setTitle(draft?.title ?? "");
      setBody(draft?.body ?? "");
      setBodyRich(draft?.bodyRich ?? null);
      setOccurrence(savedOccurrence);
      titleRef.current = draft?.title ?? "";
      occurrenceRef.current = savedOccurrence;
      setHasLocalDraft(Boolean(draft));
      replacePendingEntries(queue);
      setShowPendingEntries(queue.length > 0);
      setIsLocalStateReady(true);

      if (queue.length > 0 && navigator.onLine) {
        void synchronizeQueue();
      }

      void (async () => {
        try {
          const storedPhotos = await loadInboxPhotoDrafts(ownerId);
          if (isCanceled) return;

          const queuedPhotoIds = new Set(
            queue.flatMap((entry) =>
              entry.attachments.map((attachment) => attachment.id),
            ),
          );
          const draftPhotos = storedPhotos.filter(
            (photo) => !queuedPhotoIds.has(photo.id),
          );

          setPhotos(draftPhotos);
          setHasLocalDraft(Boolean(draft) || draftPhotos.length > 0);
        } catch {
          if (isCanceled) return;
          setIsPhotoStorageAvailable(false);
          setFeedback({
            isError: true,
            message:
              "Photo drafts are unavailable in this browser. Text capture still works.",
          });
        } finally {
          if (!isCanceled) setIsPhotoStateReady(true);
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
  }, [active, ownerId, replacePendingEntries, synchronizeQueue]);

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
  }, [active]);

  function updateDraft(
    nextTitle: string,
    nextBody: string,
    nextOccurrence: OccurrenceDraft | null,
    preserveVoiceFeedback = false,
    nextBodyRich: EntryRichText | null = nextBody === body ? bodyRich : null,
  ) {
    titleRef.current = nextTitle;
    occurrenceRef.current = nextOccurrence;
    setTitle(nextTitle);
    setBody(nextBody);
    setBodyRich(nextBodyRich);
    setOccurrence(nextOccurrence);
    setHasLocalDraft(
      persistInboxDraft(window.localStorage, ownerId, {
        body: nextBody,
        bodyRich: nextBodyRich,
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
    onNativePhotoPickerChange?.("selected");
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
      bodyRich: bodyRich?.text === parsedInput.data.body ? bodyRich : null,
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
    setBodyRich(null);
    setOccurrence(null);
    titleRef.current = "";
    occurrenceRef.current = null;
    setPhotos([]);
    setHasLocalDraft(false);
    setVoiceFeedback(null);
    setFeedback(idleFeedback);
    if (!navigator.onLine) {
      setShowPendingEntries(true);
      notify.info("Saved on this device. Waiting for a connection.");
    }
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
        className={`${captureComposerStyles.captureCard} ${variant === "dialog" ? captureComposerStyles.dialogCaptureCard : ""} ${embedded ? captureComposerStyles.embeddedCaptureCard : ""}`}
        aria-label="Quick capture"
        onKeyDownCapture={(event) => {
          if (
            !active ||
            event.defaultPrevented ||
            event.key !== "Enter" ||
            (!event.metaKey && !event.ctrlKey) ||
            event.altKey ||
            event.shiftKey ||
            event.nativeEvent.isComposing ||
            (event.target instanceof Element &&
              event.target.closest("[data-escape-layer]"))
          )
            return;

          // Capture before Tiptap's Mod-Enter hard-break/code-block bindings.
          // Shift-Enter and ordinary Enter keep the editor's newline behavior.
          event.preventDefault();
          event.stopPropagation();
          if (event.repeat) return;
          const submitButton = submitButtonRef.current;
          if (submitButton && !submitButton.disabled)
            event.currentTarget.requestSubmit(submitButton);
        }}
        onSubmit={handleSubmit}
      >
        {variant === "page" ? (
          <header className={captureComposerStyles.captureComposerHeader}>
            <span
              className={captureComposerStyles.captureSpark}
              aria-hidden="true"
            >
              <Icon name="sparkle" size={17} />
            </span>
            <h2>What’s on your mind?</h2>
          </header>
        ) : null}
        <div className={captureComposerStyles.captureIntro}>
          <div className={captureComposerStyles.captureFields}>
            {isLocalStateReady ? (
              <RichTextEditor
                autoFocus={variant === "dialog" && active}
                disabled={isSaving || voiceState !== "idle"}
                label="Entry text"
                maxLength={entryBodyLimit}
                onChange={(value) =>
                  updateDraft(title, value.text, occurrence, false, value)
                }
                placeholder="What is on your mind?"
                richText={bodyRich}
                text={body}
                variant={variant}
              />
            ) : (
              <div
                aria-label="Preparing writing space"
                className={captureComposerStyles.captureEditorLoading}
                role="status"
              />
            )}
          </div>
        </div>
        {occurrence ? (
          <div
            className={`${entryFormStyles.reviewForm} ${captureComposerStyles.captureOccurrencePanel}`}
          >
            <OccurrenceEditor
              value={occurrence}
              onChange={(value) => updateDraft(title, body, value)}
              disabled={isSaving || !isLocalStateReady || voiceState !== "idle"}
            />
            <Button
              variant="secondary"
              disabled={isSaving || !isLocalStateReady || voiceState !== "idle"}
              onClick={() => updateDraft(title, body, null)}
              type="button"
            >
              Use capture time
            </Button>
          </div>
        ) : null}
        {photos.length > 0 ? (
          <div
            className={captureComposerStyles.capturePhotoStrip}
            aria-label="Draft photos"
          >
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
            className={`${captureComposerStyles.captureVoiceStatus} ${voiceFeedback.isError ? captureComposerStyles.captureVoiceError : ""}`}
            role={voiceFeedback.isError ? "alert" : "status"}
          >
            <Icon name={voiceFeedback.isError ? "mic" : "sparkle"} size={15} />
            {voiceFeedback.message}
          </p>
        ) : null}
        <div
          className={captureComposerStyles.captureActions}
          data-capture-actions
        >
          <div>
            <button
              aria-pressed={Boolean(occurrence)}
              className={`${captureComposerStyles.quietButton} ${occurrence ? captureComposerStyles.activeQuietButton : ""}`}
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
              className={`${captureComposerStyles.quietButton} ${voiceState === "listening" ? captureComposerStyles.listeningQuietButton : ""}`}
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
              className={`${captureComposerStyles.quietButton} ${photos.length > 0 ? captureComposerStyles.activeQuietButton : ""}`}
              disabled={
                isSaving ||
                !isLocalStateReady ||
                !isPhotoStateReady ||
                !isPhotoStorageAvailable ||
                voiceState !== "idle"
              }
              onClick={() => {
                onNativePhotoPickerChange?.("opened");
                photoInputRef.current?.click();
              }}
              type="button"
            >
              <Icon name="photo" />
              <span>
                {photos.length > 0 ? `Photo · ${photos.length}` : "Photo"}
              </span>
            </button>
            <input
              accept="image/jpeg,image/png,image/webp,image/heic,image/heif"
              className={captureComposerStyles.visuallyHidden}
              disabled={
                isSaving ||
                !isLocalStateReady ||
                !isPhotoStateReady ||
                !isPhotoStorageAvailable ||
                voiceState !== "idle"
              }
              multiple
              onChange={(event) => void handlePhotoSelection(event)}
              ref={photoInputRef}
              type="file"
            />
          </div>
          <div className={captureComposerStyles.captureSubmitGroup}>
            {photoUploadProgress ? (
              <PhotoUploadProgress progress={photoUploadProgress} />
            ) : null}
            <p
              className={
                composerFeedback.isError
                  ? captureComposerStyles.captureError
                  : captureComposerStyles.captureStatus
              }
              aria-live="polite"
            >
              {composerFeedback.message}
            </p>
            <Button
              aria-keyshortcuts="Meta+Enter Control+Enter"
              variant="primary"
              disabled={
                isSaving ||
                isSyncing ||
                !isLocalStateReady ||
                !isPhotoStateReady ||
                voiceState !== "idle"
              }
              ref={submitButtonRef}
              title="Save to Inbox (⌘ Return / Ctrl+Enter)"
              type="submit"
            >
              {isSaving || isSyncing ? "Saving…" : "Save to Inbox"}
              <Icon name="chevron" size={16} />
            </Button>
          </div>
        </div>
      </form>

      {showPendingEntries && pendingEntries.length > 0 ? (
        <section
          className={captureComposerStyles.pendingSection}
          aria-labelledby={`${idPrefix}-pending-heading`}
        >
          <div className={entryListStyles.sectionHeader}>
            <div>
              <h2 id={`${idPrefix}-pending-heading`}>Pending sync</h2>
              <span>{pendingCountLabel(pendingEntries.length)}</span>
            </div>
            <Button
              variant="secondary"
              disabled={isSyncing}
              onClick={() => void synchronizeQueue()}
              type="button"
            >
              <Icon name="refresh" size={14} />
              {isSyncing ? "Syncing…" : "Retry now"}
            </Button>
          </div>
          <div className={entryListStyles.entryList}>
            {pendingEntries.map((entry) => (
              <article
                className={captureComposerStyles.pendingEntryCard}
                key={entry.id}
              >
                <div className={entryFormStyles.entryMeta}>
                  <time dateTime={entry.occurredAt ?? undefined}>
                    {occurrenceLabel(queuedOccurrence(entry))}
                  </time>
                  <Badge>On this device</Badge>
                </div>
                <h3>{entry.title ?? "Untitled Entry"}</h3>
                {entry.body ? <p>{entry.body}</p> : null}
                {entry.attachments.length > 0 ? (
                  <span className={captureComposerStyles.pendingPhotoCount}>
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
  return (
    <div className={captureComposerStyles.capturePhoto}>
      <SelectedPhotoPreview
        alt={`Selected ${photo.file.name}`}
        file={photo.file}
      />
      <button
        aria-label={`Remove selected ${photo.file.name}`}
        className={captureComposerStyles.removePhotoButton}
        onClick={onRemove}
        type="button"
      >
        <Icon name="close" size={16} />
      </button>
    </div>
  );
}

async function synchronizeAttachments(
  ownerId: string,
  entry: QueuedInboxEntry,
  onProgress?: (progress: PhotoUploadProgressValue) => void,
): Promise<SyncInboxEntryResult> {
  const storedPhotos = await loadInboxPhotoDrafts(ownerId);
  const photosById = new Map(storedPhotos.map((photo) => [photo.id, photo]));
  const client = createClient();

  let completed = 0;
  onProgress?.({ completed, total: entry.attachments.length });
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
    completed += 1;
    onProgress?.({ completed, total: entry.attachments.length });
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
