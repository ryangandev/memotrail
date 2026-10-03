"use client";
import captureComposerStyles from "@/components/capture-composer.module.css";
import entryFormStyles from "@/components/entry-form.module.css";
import entryListStyles from "@/components/entry-list.module.css";
import { Button } from "@/components/button";
import { notify } from "@/components/app-toast";

import {
  type ChangeEvent,
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  type FormEvent,
} from "react";
import { useCaptureQueue } from "@/components/capture-provider";
import { Icon } from "@/components/icon";
import { PendingCaptureList } from "@/components/pending-captures";
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
  resolveOccurrenceDraft,
  type OccurrenceDraft,
} from "@/lib/data/occurrence";
import { entryBodyLimit, parseInboxEntryValues } from "@/lib/data/inbox-input";
import { countLabel } from "@/lib/count-label";
import type { QueuedInboxEntry } from "@/lib/data/inbox-queue";
import { hasWaitingCaptures } from "@/lib/data/inbox-sync";
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
import type { EntryRichText } from "@/lib/data/rich-text";

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
  const captureQueue = useCaptureQueue();
  const { getSnapshot: readCaptureQueue, isSyncing } = captureQueue;
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [bodyRich, setBodyRich] = useState<EntryRichText | null>(null);
  const [occurrence, setOccurrence] = useState<OccurrenceDraft | null>(null);
  const [isLocalStateReady, setIsLocalStateReady] = useState(false);
  const [hasLocalDraft, setHasLocalDraft] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [feedback, setFeedback] = useState<CaptureFeedback>(idleFeedback);
  // The shared queue keeps its latest problem; editing here dismisses it.
  const [dismissedSyncRun, setDismissedSyncRun] = useState(0);
  const [photos, setPhotos] = useState<InboxPhotoDraft[]>([]);
  const [isPhotoStateReady, setIsPhotoStateReady] = useState(false);
  const [isPhotoStorageAvailable, setIsPhotoStorageAvailable] = useState(true);
  const [isVoiceSupported, setIsVoiceSupported] = useState<boolean | null>(
    null,
  );
  const [voiceState, setVoiceState] = useState<VoiceCaptureState>("checking");
  const [voiceFeedback, setVoiceFeedback] = useState<CaptureFeedback | null>(
    null,
  );
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

  useLayoutEffect(() => {
    if (!active) return;
    const draft = loadInboxDraft(window.localStorage, ownerId);
    const queue = readCaptureQueue().items.map((item) => item.entry);
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
      setIsLocalStateReady(true);

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

    return () => {
      isCanceled = true;
    };
  }, [active, ownerId, readCaptureQueue]);

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
    setDismissedSyncRun(captureQueue.runCount);
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
      setDismissedSyncRun(captureQueue.runCount);
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
      setDismissedSyncRun(captureQueue.runCount);
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
    const nextQueue = captureQueue.enqueue(entry);

    if (!nextQueue) {
      setFeedback({
        isError: true,
        message:
          "MemoTrail could not store this Entry on this device. Your draft is still here.",
      });
      setIsSaving(false);
      return;
    }

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
    setDismissedSyncRun(captureQueue.runCount);
    if (!navigator.onLine) {
      notify.info("Saved on this device. Waiting for a connection.");
    }
    setIsSaving(false);
  }

  const syncFeedback: CaptureFeedback | null =
    captureQueue.lastError && captureQueue.runCount !== dismissedSyncRun
      ? { isError: true, message: captureQueue.lastError }
      : null;
  const composerFeedback = feedback.isError
    ? feedback
    : (syncFeedback ??
      (hasLocalDraft
        ? { isError: false, message: "Draft saved on this device." }
        : feedback));

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
            {captureQueue.photoUploadProgress ? (
              <PhotoUploadProgress
                progress={captureQueue.photoUploadProgress}
              />
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
            <span className={captureComposerStyles.saveButtonHelp}>
              <Button
                aria-describedby={`${idPrefix}-save-shortcut`}
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
                type="submit"
              >
                {isSaving || isSyncing ? "Saving…" : "Save to Inbox"}
                <Icon name="chevron" size={16} />
              </Button>
              <span
                className={captureComposerStyles.saveShortcutTooltip}
                id={`${idPrefix}-save-shortcut`}
                role="tooltip"
              >
                <span>Save to Inbox</span>
                <kbd>⌘ Return</kbd>
              </span>
            </span>
          </div>
        </div>
      </form>

      {hasWaitingCaptures(captureQueue) ? (
        <section
          className={captureComposerStyles.pendingSection}
          aria-labelledby={`${idPrefix}-pending-heading`}
        >
          <div className={entryListStyles.sectionHeader}>
            <div>
              <h2 id={`${idPrefix}-pending-heading`}>Pending sync</h2>
              <span>{countLabel(captureQueue.items.length, "Entry")}</span>
            </div>
            <Button
              variant="secondary"
              disabled={isSyncing}
              onClick={() => void captureQueue.synchronize()}
              type="button"
            >
              <Icon name="refresh" size={14} />
              {isSyncing ? "Syncing…" : "Retry now"}
            </Button>
          </div>
          <PendingCaptureList items={captureQueue.items} />
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
