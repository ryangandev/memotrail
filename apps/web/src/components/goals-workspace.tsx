"use client";
import { notify } from "@/components/app-toast";
import { FocusedEditorSurface } from "@/components/focused-editor-surface";
import { useConfirmationDialog } from "@/components/confirmation-dialog";
import {
  RecordCard,
  RecordCardBody,
  RecordCardVisual,
} from "@/components/record-card";
import { EmptyState } from "@/components/empty-state";
import { FocusedViewLayout } from "@/components/focused-view-layout";
import { SeparatedList } from "@/components/separated-list";
import { Button } from "@/components/button";
import { Badge } from "@/components/badge";

import { useEffect, useRef, useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import {
  markGoalAchieved,
  registerGoalAttachment,
  saveGoalEntry,
  trashGoalAttachment,
  trashGoalEntry,
  type GoalActionResult,
} from "@/app/goals/actions";
import styles from "@/components/goals-workspace.module.css";
import common from "@/components/record-workspace.module.css";
import { EntryPhotoField } from "@/components/entry-photo-field";
import { DatePickerField } from "@/components/date-picker-field";
import { EntryOrganizationEditor } from "@/components/entry-organization-editor";
import { Icon } from "@/components/icon";
import { ProgressiveImage } from "@/components/progressive-image";
import {
  firstTimePhotoLimit,
  firstTimePhotoSizeLimit,
  inferFirstTimeImageMimeType,
} from "@/lib/data/first-time-input";
import {
  goalStatusLabels,
  goalTargetLabel,
  type GoalAttachment,
  type GoalRecord,
} from "@/lib/data/goal-record";
import {
  goalBodyLimit,
  goalStatuses,
  goalTitleLimit,
  parseGoalAchievementInput,
  parseGoalEntryInput,
  type GoalEntryInput,
  type GoalStatus,
} from "@/lib/data/goal-record-input";
import { OccurrenceEditor } from "@/components/occurrence-editor";
import {
  type OccurrenceDraft,
  resolveOccurrenceDraft,
} from "@/lib/data/occurrence";
import {
  uploadEntryPhotos,
  type PhotoUploadProgress as PhotoUploadProgressValue,
} from "@/lib/media/upload";
import { countLabel } from "@/lib/count-label";

const goalSections: Array<{
  detail: string;
  status: GoalStatus;
  title: string;
}> = [
  {
    detail: "Things you still want to do",
    status: "active",
    title: "Want to do",
  },
  {
    detail: "Things you did",
    status: "achieved",
    title: "Done",
  },
  {
    detail: "Things you chose to set down",
    status: "let_go",
    title: "Let go",
  },
];

export function GoalsWorkspace({
  goals,
  loadError,
  ownerId,
  tagOptions,
}: {
  goals: GoalRecord[];
  loadError: string | null;
  ownerId: string;
  tagOptions: string[];
}) {
  const router = useRouter();
  const [selectedGoal, setSelectedGoal] = useState<
    GoalRecord | null | undefined
  >();
  const openCount = goals.filter((goal) => goal.status === "active").length;

  return (
    <FocusedViewLayout
      actions={
        <Button
          variant="primary"
          aria-label="Add to Want to Do"
          onClick={() => setSelectedGoal(null)}
          type="button"
        >
          <Icon name="plus" />
          <span>Add</span>
        </Button>
      }
      description={
        <>
          Keep the things you want to do, with or without a date. When you do
          one, it can become a First Time.
        </>
      }
      eyebrow={<>Someday, or soon</>}
      summary={
        <SeparatedList>
          <span>{countLabel(goals.length, "item")}</span>
          <span>{openCount} to do</span>
        </SeparatedList>
      }
      summaryLabel="Want to Do summary"
      title={<>Want to Do</>}
    >
      {loadError ? (
        <div className={common.message} role="alert">
          <Icon name="sparkle" size={22} />
          <div>
            <strong>Want to Do unavailable</strong>
            <p>{loadError}</p>
          </div>
        </div>
      ) : null}

      {!loadError && goals.length === 0 ? (
        <EmptyState
          title={<>Keep one thing you want to do</>}
          icon={
            <>
              <Icon name="sparkle" size={24} />
            </>
          }
          description={
            <>Give it a name now. Add a date or notes only if you want them.</>
          }
          onClick={() => setSelectedGoal(null)}
        />
      ) : null}

      {!loadError
        ? goalSections.map((section) => {
            const sectionGoals = goals.filter(
              (goal) => goal.status === section.status,
            );
            return sectionGoals.length > 0 ? (
              <GoalSection
                detail={section.detail}
                goals={sectionGoals}
                key={section.title}
                onSelect={(goal) => router.push(`/goals/${goal.id}`)}
                title={section.title}
              />
            ) : null;
          })
        : null}

      {selectedGoal !== undefined ? (
        <GoalEditor
          goal={selectedGoal}
          key={selectedGoal?.id ?? "new-goal"}
          onClose={() => setSelectedGoal(undefined)}
          ownerId={ownerId}
          tagOptions={tagOptions}
        />
      ) : null}
    </FocusedViewLayout>
  );
}

function GoalSection({
  detail,
  goals,
  onSelect,
  title,
}: {
  detail: string;
  goals: GoalRecord[];
  onSelect: (goal: GoalRecord) => void;
  title: string;
}) {
  return (
    <section className={common.homeSection}>
      <header>
        <h2>{title}</h2>
        <span>{detail}</span>
      </header>
      <div className={styles.goalGrid}>
        {goals.map((goal) => (
          <GoalCard goal={goal} key={goal.id} onSelect={() => onSelect(goal)} />
        ))}
      </div>
    </section>
  );
}

function GoalCard({
  goal,
  onSelect,
}: {
  goal: GoalRecord;
  onSelect: () => void;
}) {
  const cover = goal.attachments[0];
  const hasAchievement = goal.relatedEntries.some(
    (entry) => entry.relationship === "achievement",
  );

  return (
    <RecordCard
      ariaLabel={`${goal.title}, ${goalStatusLabels[goal.status]}`}
      onClick={onSelect}
    >
      {cover?.imageUrl ? (
        <RecordCardVisual className={styles.goalCover}>
          <ProgressiveImage alt="" src={cover.imageUrl} />
          {goal.attachments.length > 1 ? (
            <Badge
              className={styles.photoCount}
              size="micro"
              tone="inverse"
              uppercase
            >
              {goal.attachments.length} photos
            </Badge>
          ) : null}
        </RecordCardVisual>
      ) : null}
      <RecordCardBody className={styles.goalCardBody}>
        <h3>{goal.title}</h3>
        {goal.targetDate ? (
          <p className={styles.target}>{goalTargetLabel(goal)}</p>
        ) : null}
        {goal.body ? (
          <p className={styles.reflection}>{truncate(goal.body, 180)}</p>
        ) : null}
        <div className={styles.contextLine}>
          {hasAchievement ? <span>First Time linked</span> : null}
        </div>
        <footer>
          <div>
            {goal.tagNames.slice(0, 2).map((name) => (
              <Badge
                key={`tag:${name.toLocaleLowerCase()}`}
                size="micro"
                tone="neutral"
              >
                #{name}
              </Badge>
            ))}
          </div>
          <Icon name="chevron" size={15} />
        </footer>
      </RecordCardBody>
    </RecordCard>
  );
}

export function GoalEditor({
  goal,
  onClose,
  onTrashed,
  ownerId,
  presentation = "dialog",
  tagOptions,
}: {
  goal: GoalRecord | null;
  onClose: () => void;
  onTrashed?: () => void;
  ownerId: string;
  presentation?: "dialog" | "page";
  tagOptions: string[];
}) {
  const router = useRouter();
  const requestConfirmation = useConfirmationDialog();
  const titleRef = useRef<HTMLInputElement>(null);
  const [body, setBody] = useState(goal?.body ?? "");
  const [currentId, setCurrentId] = useState(goal?.id ?? null);
  const [currentRevision, setCurrentRevision] = useState(
    goal?.revision ?? null,
  );
  const [existingPhotos, setExistingPhotos] = useState(goal?.attachments ?? []);
  const [isPending, setIsPending] = useState(false);
  const [photoUploadProgress, setPhotoUploadProgress] =
    useState<PhotoUploadProgressValue | null>(null);
  const [pendingPhotos, setPendingPhotos] = useState<File[]>([]);
  const [result, setResult] = useState<GoalActionResult | null>(null);
  const [status, setStatus] = useState<GoalStatus>(goal?.status ?? "active");
  const [tagInput, setTagInput] = useState("");
  const [tagNames, setTagNames] = useState(goal?.tagNames ?? []);
  const [targetDate, setTargetDate] = useState(goal?.targetDate ?? "");
  const [title, setTitle] = useState(goal?.title ?? "");

  useEffect(() => {
    titleRef.current?.focus();
  }, []);

  const canRecordAchievement = Boolean(goal && status !== "achieved");
  const hasUnsavedChanges = Boolean(
    goal &&
    (title !== goal.title ||
      body !== goal.body ||
      status !== goal.status ||
      (targetDate || null) !== goal.targetDate ||
      !sameNames(tagNames, goal.tagNames) ||
      Boolean(tagInput.trim()) ||
      pendingPhotos.length > 0),
  );

  function handlePhotoSelection(selected: File[]) {
    const available = Math.max(
      0,
      firstTimePhotoLimit - existingPhotos.length - pendingPhotos.length,
    );
    const accepted: File[] = [];
    let errorMessage = "";
    for (const file of selected.slice(0, available)) {
      if (!inferFirstTimeImageMimeType(file.name, file.type)) {
        errorMessage = "Use JPEG, PNG, WebP, HEIC, or HEIF photos.";
      } else if (file.size < 1 || file.size > firstTimePhotoSizeLimit) {
        errorMessage = "Each photo must be no larger than 50 MB.";
      } else {
        accepted.push(file);
      }
    }
    if (selected.length > available) {
      errorMessage = `Keep up to ${firstTimePhotoLimit} photos on each item.`;
    }
    setPendingPhotos((current) => [...current, ...accepted]);
    setResult(errorMessage ? actionError(errorMessage) : null);
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const input: GoalEntryInput = {
      body,
      id: currentId,
      revision: currentRevision,
      status,
      tagNames: namesIncludingDraft(tagNames, tagInput),
      targetDate: targetDate || null,
      title,
    };
    const parsed = parseGoalEntryInput(input);
    if (!parsed.success) {
      setResult(actionError(parsed.message));
      return;
    }

    setIsPending(true);
    setResult(null);
    try {
      const saved = await saveGoalEntry(parsed.data);
      if (
        (saved.status !== "created" && saved.status !== "saved") ||
        !saved.entry
      ) {
        setResult(saved);
        return;
      }
      setCurrentId(saved.entry.id);
      setCurrentRevision(saved.entry.revision);
      const failedPhotos = await uploadPhotos(
        ownerId,
        saved.entry.id,
        pendingPhotos,
        setPhotoUploadProgress,
      );
      if (failedPhotos.length > 0) {
        setPendingPhotos(failedPhotos);
        setResult(
          actionError(
            `Saved, but ${countLabel(failedPhotos.length, "photo")} could not be attached. Select Save again to retry.`,
          ),
        );
        router.refresh();
        return;
      }
      router.refresh();
      notify.success(
        saved.status === "created" ? "Added to Want to Do." : "Changes saved.",
      );
      onClose();
    } catch {
      setResult(
        actionError(
          "MemoTrail could not reach the server. Try again when online.",
        ),
      );
    } finally {
      setPhotoUploadProgress(null);
      setIsPending(false);
    }
  }

  async function handleRemovePhoto(photo: GoalAttachment) {
    const confirmed = await requestConfirmation({
      title: <>Move this photo to Trash?</>,
      description: <>The original will be preserved for recovery.</>,
      confirmLabel: "Move photo to Trash",
      eyebrow: <>Recoverable action</>,
      variant: "danger",
    });
    if (!confirmed) return;
    setIsPending(true);
    setResult(null);
    try {
      const nextResult = await trashGoalAttachment({ attachmentId: photo.id });
      if (nextResult.status === "trashed") {
        setExistingPhotos((current) =>
          current.filter((item) => item.id !== photo.id),
        );
        router.refresh();
        notify.info("Photo moved to Trash.");
      } else {
        setResult(nextResult);
      }
    } catch {
      setResult(
        actionError("MemoTrail could not remove this photo. Try again."),
      );
    } finally {
      setIsPending(false);
    }
  }

  async function handleTrashEntry() {
    if (!currentId || currentRevision === null) return;
    const confirmed = await requestConfirmation({
      title: <>Move “{title.trim() || "this item"}” to Trash?</>,
      description: <>It and its private photos can be restored from Trash.</>,
      confirmLabel: "Move to Trash",
      eyebrow: <>Recoverable action</>,
      variant: "danger",
    });
    if (!confirmed) return;
    setIsPending(true);
    setResult(null);
    try {
      const nextResult = await trashGoalEntry({
        id: currentId,
        revision: currentRevision,
      });
      if (nextResult.status === "trashed") {
        onTrashed?.();
        router.refresh();
        onClose();
        notify.info("Moved to Trash.");
      } else {
        setResult(nextResult);
      }
    } catch {
      setResult(actionError("MemoTrail could not move this item to Trash."));
    } finally {
      setIsPending(false);
    }
  }

  return (
    <FocusedEditorSurface
      onClose={onClose}
      presentation={presentation}
      title={
        <>{currentId ? title || "Want to Do" : "What do you want to do?"}</>
      }
      titleId="goal-editor-title"
      eyebrow={<>{currentId ? "Edit Want to Do" : "Want to Do"}</>}
      closeLabel="Close Want to Do editor"
      busy={isPending}
      footer={
        <div className={common.dialogFooter}>
          <div>
            {currentId ? (
              <Button
                variant="danger"
                disabled={isPending}
                onClick={() => void handleTrashEntry()}
                type="button"
              >
                Move to Trash
              </Button>
            ) : null}
          </div>
          <div>
            <Button
              variant="secondary"
              disabled={isPending}
              onClick={onClose}
              type="button"
            >
              Cancel
            </Button>
            <Button
              form="goals-workspace-form"
              variant="primary"
              disabled={isPending}
              type="submit"
            >
              {isPending
                ? "Saving..."
                : currentId
                  ? "Save changes"
                  : "Add to Want to Do"}
            </Button>
          </div>
        </div>
      }
    >
      <form id="goals-workspace-form" onSubmit={handleSubmit}>
        <div className={common.formGrid}>
          <fieldset className={common.formSection}>
            <legend>What you want to do</legend>
            <label className={common.fullField}>
              <span>
                Title <span aria-hidden="true">*</span>
              </span>
              <input
                aria-label="Title"
                maxLength={goalTitleLimit}
                onChange={(event) => setTitle(event.target.value)}
                placeholder="Learn to sail"
                ref={titleRef}
                required
                value={title}
              />
            </label>
            {currentId ? (
              <label>
                <span>Status</span>
                <select
                  onChange={(event) =>
                    setStatus(event.target.value as GoalStatus)
                  }
                  value={status}
                >
                  {goalStatuses.map((value) => (
                    <option key={value} value={value}>
                      {goalStatusLabels[value]}
                    </option>
                  ))}
                </select>
              </label>
            ) : null}
            <DatePickerField
              disabled={isPending}
              label="Target date"
              onChange={setTargetDate}
              value={targetDate}
            />
            <label className={common.fullField}>
              <span>Notes</span>
              <textarea
                maxLength={goalBodyLimit}
                onChange={(event) => setBody(event.target.value)}
                placeholder="Why it matters, or anything you want to remember about it."
                rows={6}
                value={body}
              />
            </label>
            <EntryOrganizationEditor
              disabled={isPending}
              input={tagInput}
              names={tagNames}
              onChange={setTagNames}
              onInputChange={setTagInput}
              options={tagOptions}
            />
          </fieldset>

          <EntryPhotoField
            disabled={isPending}
            existingPhotos={existingPhotos}
            limit={firstTimePhotoLimit}
            onRemoveExisting={(photo) => void handleRemovePhoto(photo)}
            onRemovePending={(index) =>
              setPendingPhotos((current) =>
                current.filter((_, itemIndex) => itemIndex !== index),
              )
            }
            onSelect={handlePhotoSelection}
            pendingPhotos={pendingPhotos}
            progress={photoUploadProgress}
            recordLabel="Want to Do"
          />

          {canRecordAchievement && currentId && currentRevision !== null ? (
            <AchievementPanel
              disabled={isPending}
              goalId={currentId}
              revision={currentRevision}
              unsavedChanges={hasUnsavedChanges}
              onAchieved={(nextResult) => {
                if (nextResult.entry) {
                  setCurrentRevision(nextResult.entry.revision);
                  setStatus("achieved");
                }
                if (nextResult.status === "achieved") {
                  setResult(null);
                  notify.success(nextResult.message);
                } else setResult(nextResult);
                router.refresh();
              }}
              onPendingChange={setIsPending}
            />
          ) : null}
        </div>

        {result ? (
          <p className={common.formMessage} role="status">
            {result.message}
          </p>
        ) : null}
      </form>
    </FocusedEditorSurface>
  );
}

function AchievementPanel({
  disabled,
  goalId,
  onAchieved,
  onPendingChange,
  revision,
  unsavedChanges,
}: {
  disabled: boolean;
  goalId: string;
  onAchieved: (result: GoalActionResult) => void;
  onPendingChange: (pending: boolean) => void;
  revision: number;
  unsavedChanges: boolean;
}) {
  const [occurrence, setOccurrence] = useState<OccurrenceDraft>(() => ({
    precision: "unknown",
    start: "",
    end: "",
    label: "",
    timezone: localTimezone(),
  }));
  const [localError, setLocalError] = useState<string | null>(null);

  async function handleAchievement() {
    const resolved = resolveOccurrenceDraft(occurrence);
    if (!resolved.value) {
      setLocalError(resolved.error);
      return;
    }
    const parsed = parseGoalAchievementInput({
      datePrecision: resolved.value.datePrecision,
      id: goalId,
      occurredLabel: resolved.value.occurredLabel,
      occurredStart: resolved.value.occurredAt,
      occurredEnd: resolved.value.occurredEnd,
      occurredTimezone: resolved.value.occurredTimezone,
      revision,
    });
    if (!parsed.success) {
      setLocalError(parsed.message);
      return;
    }

    onPendingChange(true);
    setLocalError(null);
    try {
      onAchieved(await markGoalAchieved(parsed.data));
    } catch {
      setLocalError(
        "MemoTrail could not reach the server. Try again when online.",
      );
    } finally {
      onPendingChange(false);
    }
  }

  return (
    <fieldset className={`${common.formSection} ${styles.achievementPanel}`}>
      <legend>Done it?</legend>
      <div className={styles.achievementIntro}>
        <span>
          <Icon name="star" size={18} />
        </span>
        <div>
          <strong>Mark it done and keep it as a First Time</strong>
          <p>
            MemoTrail marks this Done and adds a linked First Time with the same
            title. Your notes stay here.
          </p>
        </div>
      </div>
      <OccurrenceEditor
        value={occurrence}
        onChange={setOccurrence}
        disabled={disabled}
      />
      {localError ? (
        <p className={styles.achievementError} role="alert">
          {localError}
        </p>
      ) : null}
      {unsavedChanges ? (
        <p className={styles.achievementNote}>
          Save your other changes before marking this done.
        </p>
      ) : null}
      <Button
        variant="primary"
        className={styles.achievementAction}
        disabled={disabled || unsavedChanges}
        onClick={() => void handleAchievement()}
        type="button"
      >
        <Icon name="check" size={16} />
        Mark done and add First Time
      </Button>
    </fieldset>
  );
}

async function uploadPhotos(
  ownerId: string,
  entryId: string,
  photos: File[],
  onProgress: (progress: PhotoUploadProgressValue) => void,
) {
  return uploadEntryPhotos(
    ownerId,
    entryId,
    photos,
    registerGoalAttachment,
    onProgress,
  );
}

function namesIncludingDraft(names: string[], draft: string) {
  const name = draft.trim();
  return name ? [...names, name] : names;
}

function sameNames(first: string[], second: string[]) {
  return (
    first.length === second.length &&
    first.every((value, index) => value === second[index])
  );
}

function localTimezone() {
  return Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
}

function actionError(message: string): GoalActionResult {
  return {
    entry: null,
    firstTimeEntryId: null,
    message,
    status: "error",
  };
}

function truncate(value: string, limit: number) {
  return value.length > limit ? `${value.slice(0, limit).trimEnd()}...` : value;
}
