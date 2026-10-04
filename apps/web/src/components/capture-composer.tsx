"use client";
import captureComposerStyles from "@/components/capture-composer.module.css";
import entryFormStyles from "@/components/entry-form.module.css";
import entryListStyles from "@/components/entry-list.module.css";
import { Button } from "@/components/button";
import { notify } from "@/components/app-toast";

import {
  type ChangeEvent,
  useEffect,
  useRef,
  useState,
  type FormEvent,
} from "react";
import {
  useCaptureDraft,
  useCaptureQueue,
} from "@/components/capture-provider";
import { Icon } from "@/components/icon";
import { PendingCaptureList } from "@/components/pending-captures";
import { PhotoUploadProgress } from "@/components/photo-upload-progress";
import { RichTextEditor } from "@/components/rich-text-editor";
import { SelectedPhotoPreview } from "@/components/selected-photo-preview";
import { OccurrenceEditor } from "./occurrence-editor";
import { occurrenceDraft, resolveOccurrenceDraft } from "@/lib/data/occurrence";
import { entryBodyLimit, parseInboxEntryValues } from "@/lib/data/inbox-input";
import { countLabel } from "@/lib/count-label";
import type { QueuedInboxEntry } from "@/lib/data/inbox-queue";
import {
  countPendingCaptures,
  hasWaitingCaptures,
} from "@/lib/data/inbox-sync";
import {
  queuedInboxAttachment,
  validateInboxPhotoFiles,
  type InboxPhotoDraft,
} from "@/lib/data/inbox-photo";
import { browserSpeechRecognitionConstructor } from "@/lib/data/voice-transcript";
import { trimEntryNote } from "@/lib/data/rich-text";

type CaptureFeedback = {
  isError: boolean;
  message: string;
};

type VoiceCaptureState = "checking" | "idle" | "listening" | "stopping";

export type NativePhotoPickerState = "canceled" | "opened" | "selected";

const idleFeedback: CaptureFeedback = { isError: false, message: "" };

/**
 * Composes a capture in the workspace's shared draft: every composer in the
 * tab shows the same writing, date, photos, and voice capture, so a save or a
 * discard in one is reflected in all of them.
 */
export function CaptureComposer({
  active = true,
  embedded = false,
  idPrefix = "capture",
  onNativePhotoPickerChange,
  variant = "page",
}: {
  active?: boolean;
  embedded?: boolean;
  idPrefix?: string;
  onNativePhotoPickerChange?: (state: NativePhotoPickerState) => void;
  variant?: "dialog" | "page";
}) {
  const captureQueue = useCaptureQueue();
  const { isSyncing } = captureQueue;
  const draft = useCaptureDraft();
  const { body, bodyRich, cancelVoice, occurrence, photos, title } = draft;
  const [isSaving, setIsSaving] = useState(false);
  // A message about this composer's own action, shown until the draft changes.
  const [feedback, setFeedback] = useState<
    (CaptureFeedback & { revision: number }) | null
  >(null);
  // The shared queue keeps its latest problem; any change to the draft, here
  // or in another composer, dismisses it.
  const [draftRevision, setDraftRevision] = useState(draft.revision);
  const [dismissedSyncRun, setDismissedSyncRun] = useState(0);
  if (draft.revision !== draftRevision) {
    setDraftRevision(draft.revision);
    setDismissedSyncRun(captureQueue.runCount);
  }
  const [isVoiceSupported, setIsVoiceSupported] = useState<boolean | null>(
    null,
  );
  const voiceState: VoiceCaptureState =
    isVoiceSupported === null ? "checking" : draft.voice;
  const isPhotoStateReady = draft.photoState !== "loading";
  const isPhotoStorageAvailable = draft.photoState !== "unavailable";
  const photoInputRef = useRef<HTMLInputElement>(null);
  const submitButtonRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    const input = photoInputRef.current;
    if (!input || !onNativePhotoPickerChange) return;

    function handlePhotoPickerCancel() {
      onNativePhotoPickerChange?.("canceled");
    }

    input.addEventListener("cancel", handlePhotoPickerCancel);
    return () => input.removeEventListener("cancel", handlePhotoPickerCancel);
  }, [onNativePhotoPickerChange]);

  useEffect(() => {
    let isCanceled = false;

    queueMicrotask(() => {
      if (!isCanceled)
        setIsVoiceSupported(
          Boolean(browserSpeechRecognitionConstructor(window)),
        );
    });

    return () => {
      isCanceled = true;
    };
  }, []);

  // Closing Quick Capture or leaving the Dashboard ends voice capture, even
  // when another composer started it.
  useEffect(() => {
    if (!active) return;
    return cancelVoice;
  }, [active, cancelVoice]);

  /** Shows a message about this composer's action until the draft changes. */
  function showFeedback(message: CaptureFeedback) {
    setFeedback({ ...message, revision: draft.getSnapshot().revision });
  }

  function startVoiceCapture() {
    if (!browserSpeechRecognitionConstructor(window))
      setIsVoiceSupported(false);
    draft.startVoice();
  }

  function toggleRelevantDate() {
    draft.update({
      occurrence: occurrence
        ? null
        : occurrenceDraft({
            datePrecision: "exact",
            occurredAt: new Date().toISOString(),
            occurredEnd: null,
            occurredLabel: null,
            occurredTimezone:
              Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC",
          }),
    });
  }

  async function handlePhotoSelection(event: ChangeEvent<HTMLInputElement>) {
    onNativePhotoPickerChange?.("selected");
    const selection = validateInboxPhotoFiles(
      Array.from(event.target.files ?? []),
      photos.length,
    );
    event.target.value = "";

    if (selection.accepted.length === 0) {
      if (selection.message) {
        showFeedback({ isError: true, message: selection.message });
      }
      return;
    }

    try {
      await draft.addPhotos(selection.accepted);
      showFeedback({
        isError: Boolean(selection.message),
        message: selection.message ?? "Photos saved in this draft.",
      });
    } catch {
      showFeedback({
        isError: true,
        message:
          "This browser could not keep those photos safely. Try another browser or device.",
      });
    }
  }

  async function removePhoto(photoId: string) {
    try {
      await draft.removePhoto(photoId);
    } catch {
      showFeedback({
        isError: true,
        message: "MemoTrail could not remove that local photo. Try again.",
      });
    }
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const note = trimEntryNote(body, bodyRich);
    const parsedInput = parseInboxEntryValues({
      body: note.body,
      hasAttachments: photos.length > 0,
      title,
    });

    if (!parsedInput.success) {
      showFeedback({ isError: true, message: parsedInput.message });
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
      showFeedback({ isError: true, message: parsedDate.error });
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
      bodyRich: note.bodyRich,
      version: 3,
    };
    const nextQueue = captureQueue.enqueue(entry);

    if (!nextQueue) {
      showFeedback({
        isError: true,
        message:
          "MemoTrail could not store this Entry on this device. Your draft is still here.",
      });
      setIsSaving(false);
      return;
    }

    // Every composer empties together, so none can save this capture again.
    draft.clear();
    if (!navigator.onLine) {
      notify.info("Saved on this device. Waiting for a connection.");
    }
    setIsSaving(false);
  }

  const syncFeedback: CaptureFeedback | null =
    captureQueue.lastError && captureQueue.runCount !== dismissedSyncRun
      ? { isError: true, message: captureQueue.lastError }
      : null;
  const currentFeedback =
    (feedback?.revision === draft.revision ? feedback : null) ??
    (draft.notice?.revision === draft.revision ? draft.notice : null) ??
    idleFeedback;
  const composerFeedback = currentFeedback.isError
    ? currentFeedback
    : (syncFeedback ??
      (draft.hasLocalDraft
        ? { isError: false, message: "Draft saved on this device." }
        : currentFeedback));
  const voiceFeedback = draft.voiceNotice;

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
            {draft.isReady ? (
              <RichTextEditor
                autoFocus={variant === "dialog" && active}
                disabled={isSaving || voiceState !== "idle"}
                label="Entry text"
                maxLength={entryBodyLimit}
                onChange={(value) =>
                  draft.update({ body: value.text, bodyRich: value })
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
              onChange={(value) => draft.update({ occurrence: value })}
              disabled={isSaving || !draft.isReady || voiceState !== "idle"}
            />
            <Button
              variant="secondary"
              disabled={isSaving || !draft.isReady || voiceState !== "idle"}
              onClick={() => draft.update({ occurrence: null })}
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
              disabled={isSaving || !draft.isReady || voiceState !== "idle"}
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
                !draft.isReady ||
                voiceState === "checking" ||
                voiceState === "stopping"
              }
              onClick={
                voiceState === "listening" ? draft.stopVoice : startVoiceCapture
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
                !draft.isReady ||
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
                !draft.isReady ||
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
                  !draft.isReady ||
                  !isPhotoStateReady ||
                  voiceState !== "idle"
                }
                ref={submitButtonRef}
                type="submit"
              >
                {isSaving || isSyncing ? "Saving…" : "Save to Library"}
                <Icon name="chevron" size={16} />
              </Button>
              <span
                className={captureComposerStyles.saveShortcutTooltip}
                id={`${idPrefix}-save-shortcut`}
                role="tooltip"
              >
                <span>Save to Library</span>
                <kbd>⌘ Return</kbd>
              </span>
            </span>
          </div>
        </div>
      </form>

      {hasWaitingCaptures(captureQueue) ? (
        <section
          className={`${captureComposerStyles.pendingSection} ${variant === "dialog" ? captureComposerStyles.dialogPendingSection : ""}`}
          aria-labelledby={`${idPrefix}-pending-heading`}
        >
          <div className={entryListStyles.sectionHeader}>
            <div>
              <h2 id={`${idPrefix}-pending-heading`}>Pending sync</h2>
              <span>{countLabel(captureQueue.items.length, "Entry")}</span>
            </div>
            {/* Captures MemoTrail did not accept are never retried. */}
            {countPendingCaptures(captureQueue.items).waiting > 0 ? (
              <Button
                variant="secondary"
                disabled={isSyncing}
                onClick={() => void captureQueue.synchronize()}
                type="button"
              >
                <Icon name="refresh" size={14} />
                {isSyncing ? "Syncing…" : "Retry now"}
              </Button>
            ) : null}
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
