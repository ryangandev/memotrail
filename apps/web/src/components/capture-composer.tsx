"use client";
import captureComposerStyles from "@/components/capture-composer.module.css";
import { Button } from "@/components/button";
import { notify } from "@/components/app-toast";
import {
  captureComposerDefaults,
  type CaptureComposerVariant,
} from "@/generated/design-system";

import {
  type ChangeEvent,
  type FocusEvent,
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
import { SectionHeader } from "@/components/section-header";
import { Skeleton } from "@/components/skeleton";
import { SelectedPhotoPreview } from "@/components/selected-photo-preview";
import { DatePickerField } from "@/components/date-picker-field";
import {
  captureDateDraft,
  captureDateValue,
  resolveCaptureDate,
  todayCaptureDate,
} from "@/lib/data/inbox-capture-date";
import type { OccurrenceDraft } from "@/lib/data/occurrence";
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
 * discard in one is reflected in all of them. Specified in
 * packages/design-system/components/capture-composer.yaml.
 */
export function CaptureComposer({
  active = true,
  embedded = false,
  idPrefix = "capture",
  onNativePhotoPickerChange,
  variant = captureComposerDefaults.variant,
}: {
  active?: boolean;
  embedded?: boolean;
  idPrefix?: string;
  onNativePhotoPickerChange?: (state: NativePhotoPickerState) => void;
  variant?: CaptureComposerVariant;
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
  // The formatting toolbar appears once the composer is in use, so the resting card reads as a
  // single quiet field. Quick Capture opens already in use.
  const [isEngaged, setIsEngaged] = useState(variant === "dialog");
  const isPointerDown = useRef(false);
  const showToolbar =
    variant === "dialog" || isEngaged || body.trim().length > 0;

  // Only writing, not pressing a tool, brings the toolbar in: it would move the tool under the
  // pointer before the press finishes.
  function handleFocus(event: FocusEvent<HTMLFormElement>) {
    if (
      event.target instanceof Element &&
      event.target.closest("[data-rich-text-editor]")
    )
      setIsEngaged(true);
  }

  function handleBlur(event: FocusEvent<HTMLFormElement>) {
    // Pressing a tool moves focus off the writing field for a moment; keep the toolbar so the
    // layout does not shift under the press.
    if (
      isPointerDown.current ||
      event.currentTarget.contains(event.relatedTarget as Node | null)
    )
      return;
    setIsEngaged(false);
  }

  function handlePointerDown() {
    isPointerDown.current = true;
    window.addEventListener(
      "pointerup",
      () => {
        isPointerDown.current = false;
      },
      { once: true },
    );
  }

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

  // Choosing a date starts on today; turning it off saves the capture time.
  function toggleDate() {
    draft.update({
      occurrence: occurrence
        ? null
        : todayCaptureDate(new Date(), browserTimezone()),
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
    const parsedDate = resolveCaptureDate(occurrence, now, browserTimezone());

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
        data-toolbar={showToolbar ? "shown" : "hidden"}
        data-ui-capture-composer
        data-variant={variant}
        onBlur={handleBlur}
        onFocus={handleFocus}
        onPointerDownCapture={handlePointerDown}
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
                placeholder="What’s on your mind?"
                richText={bodyRich}
                text={body}
                variant="embedded"
              />
            ) : (
              <div
                aria-label="Preparing writing space"
                className={captureComposerStyles.captureEditorLoading}
                role="status"
              >
                <Skeleton height="auto" shape="fill" />
              </div>
            )}
          </div>
        </div>
        {occurrence ? (
          <div
            aria-label="Date"
            className={captureComposerStyles.captureDatePanel}
            role="group"
          >
            <DatePickerField
              disabled={isSaving || !draft.isReady || voiceState !== "idle"}
              hideLabel
              includeTime
              label="Date"
              onChange={(value) =>
                draft.update({
                  occurrence: captureDateDraft(value, occurrence.timezone),
                })
              }
              value={captureDateValue(occurrence)}
            />
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
          <div className={captureComposerStyles.captureTools}>
            <button
              aria-pressed={Boolean(occurrence)}
              className={`${captureComposerStyles.chip} ${occurrence ? captureComposerStyles.activeChip : ""}`}
              data-capture-date-toggle
              disabled={isSaving || !draft.isReady || voiceState !== "idle"}
              onClick={toggleDate}
              type="button"
            >
              <Icon name="calendar" size={15} />
              <span>{dateChipLabel(occurrence)}</span>
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
              className={`${captureComposerStyles.chip} ${captureComposerStyles.voiceChip} ${voiceState === "listening" ? captureComposerStyles.listeningChip : ""}`}
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
              <Icon
                name={voiceState === "listening" ? "stop" : "mic"}
                size={15}
              />
              <span>{voiceState === "listening" ? "Stop" : "Voice"}</span>
            </button>
            <button
              aria-label="Add photos"
              aria-pressed={photos.length > 0}
              className={`${captureComposerStyles.chip} ${photos.length > 0 ? captureComposerStyles.activeChip : ""}`}
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
              <Icon name="photo" size={15} />
              <span>
                {photos.length > 0 ? `Photos · ${photos.length}` : "Photos"}
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
            {variant === "page" ? (
              <span
                className={captureComposerStyles.saveShortcutHint}
                id={`${idPrefix}-save-shortcut`}
              >
                <kbd>⌘ Return</kbd>
              </span>
            ) : null}
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
                {isSaving || isSyncing ? "Saving…" : "Save"}
              </Button>
              {variant === "dialog" ? (
                <span
                  className={captureComposerStyles.saveShortcutTooltip}
                  id={`${idPrefix}-save-shortcut`}
                  role="tooltip"
                >
                  <span>Save</span>
                  <kbd>⌘ Return</kbd>
                </span>
              ) : null}
            </span>
          </div>
        </div>
        <p
          aria-live="polite"
          className={
            composerFeedback.isError
              ? captureComposerStyles.captureError
              : captureComposerStyles.captureStatus
          }
        >
          {composerFeedback.message}
        </p>
      </form>

      {hasWaitingCaptures(captureQueue) ? (
        <section
          className={`${captureComposerStyles.pendingSection} ${variant === "dialog" ? captureComposerStyles.dialogPendingSection : ""}`}
          aria-labelledby={`${idPrefix}-pending-heading`}
        >
          <SectionHeader
            action={
              // Captures MemoTrail did not accept are never retried.
              countPendingCaptures(captureQueue.items).waiting > 0 ? (
                <Button
                  variant="secondary"
                  size="small"
                  disabled={isSyncing}
                  onClick={() => void captureQueue.synchronize()}
                  type="button"
                >
                  <Icon name="refresh" size={14} />
                  {isSyncing ? "Syncing…" : "Retry now"}
                </Button>
              ) : null
            }
            className={captureComposerStyles.pendingHeader}
            detail={countLabel(
              captureQueue.items.length + captureQueue.unreadable.length,
              "Entry",
            )}
            headingId={`${idPrefix}-pending-heading`}
            title="Pending sync"
            variant={variant === "dialog" ? "list" : "section"}
          />
          <PendingCaptureList
            items={captureQueue.items}
            unreadable={captureQueue.unreadable}
          />
        </section>
      ) : null}
    </>
  );
}

/** "Today" until a day is chosen, then that day, with its time when one is set. */
function dateChipLabel(occurrence: OccurrenceDraft | null) {
  const value = occurrence ? captureDateValue(occurrence) : "";
  if (!value) return "Today";
  const [day, time] = value.split("T");
  const [year, month, date] = day.split("-").map(Number);
  const label = new Intl.DateTimeFormat("en-US", {
    day: "numeric",
    month: "short",
    timeZone: "UTC",
    year: year === new Date().getFullYear() ? undefined : "numeric",
  }).format(new Date(Date.UTC(year, month - 1, date)));
  if (!time) return label;
  const [hours, minutes] = time.split(":").map(Number);
  const clock = new Intl.DateTimeFormat("en-US", {
    hour: "numeric",
    minute: "2-digit",
    timeZone: "UTC",
  }).format(new Date(Date.UTC(1970, 0, 1, hours, minutes)));
  return `${label}, ${clock}`;
}

function browserTimezone() {
  return Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
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
