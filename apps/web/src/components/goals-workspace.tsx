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

import { useEffect, useMemo, useRef, useState, type FormEvent } from "react";
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
  goalHorizonLabels,
  goalStatusLabels,
  goalTargetLabel,
  isBucketListGoal,
  type GoalAttachment,
  type GoalLinkOption,
  type GoalRecord,
} from "@/lib/data/goal-record";
import {
  goalBodyLimit,
  goalHorizons,
  goalStatuses,
  goalTitleLimit,
  parseGoalAchievementInput,
  parseGoalEntryInput,
  type GoalEntryInput,
  type GoalHorizon,
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
import {
  pendingCaptureReference,
  type CaptureExtractionSource,
} from "@/lib/data/capture-extraction-input";
import { wikiItemIdentityLabel } from "@/lib/data/wiki-item";
import { countLabel } from "@/lib/count-label";

const goalSections: Array<{
  detail: string;
  statuses: GoalStatus[];
  title: string;
}> = [
  {
    detail: "Intentions you are actively carrying",
    statuses: ["active"],
    title: "In motion",
  },
  {
    detail: "Possibilities worth keeping near",
    statuses: ["considering"],
    title: "Considering",
  },
  {
    detail: "Ideas resting without pressure",
    statuses: ["paused"],
    title: "Paused",
  },
  {
    detail: "What was achieved or consciously released",
    statuses: ["achieved", "let_go"],
    title: "Closed chapters",
  },
];

export function GoalsWorkspace({
  collectionOptions,
  goals,
  initialGoalId,
  linkOptions,
  loadError,
  ownerId,
  sourceCapture,
  tagOptions,
}: {
  collectionOptions: string[];
  goals: GoalRecord[];
  initialGoalId: string | null;
  linkOptions: GoalLinkOption[];
  loadError: string | null;
  ownerId: string;
  sourceCapture: CaptureExtractionSource | null;
  tagOptions: string[];
}) {
  const router = useRouter();
  // Creating the Goal organizes the Capture, so the revalidated page no longer
  // returns it. The open editor keeps the handoff it started with.
  const [captureHandoff, setCaptureHandoff] = useState(sourceCapture);
  const [selectedGoal, setSelectedGoal] = useState<
    GoalRecord | null | undefined
  >(sourceCapture ? null : goals.find((goal) => goal.id === initialGoalId));
  const openCount = goals.filter(
    (goal) => !["achieved", "let_go"].includes(goal.status),
  ).length;
  const bucketCount = goals.filter(isBucketListGoal).length;

  return (
    <FocusedViewLayout
      actions={
        <Button
          variant="primary"
          aria-label="Add Goal"
          onClick={() => setSelectedGoal(null)}
          type="button"
        >
          <Icon name="plus" />
          <span>Add Goal</span>
        </Button>
      }
      description={
        <>
          Keep near-term plans, distant hopes, and someday ideas together as
          part of your personal archive.
        </>
      }
      eyebrow={<>Intentions without pressure</>}
      summary={
        <SeparatedList>
          <span>{countLabel(goals.length, "goal")}</span>
          <span>{openCount} open</span>
          <span>{bucketCount} in Bucket List</span>
        </SeparatedList>
      }
      summaryLabel="Goals summary"
      title={<>Goals</>}
    >
      {loadError ? (
        <div className={common.message} role="alert">
          <Icon name="sparkle" size={22} />
          <div>
            <strong>Goals unavailable</strong>
            <p>{loadError}</p>
          </div>
        </div>
      ) : null}

      {!loadError && goals.length === 0 ? (
        <EmptyState
          title={<>Keep one possibility close</>}
          icon={
            <>
              <Icon name="sparkle" size={24} />
            </>
          }
          description={
            <>
              Give it a name now. Its horizon, context, and meaning can evolve
              with you.
            </>
          }
          onClick={() => setSelectedGoal(null)}
        />
      ) : null}

      {!loadError
        ? goalSections.map((section) => {
            const sectionGoals = goals.filter((goal) =>
              section.statuses.includes(goal.status),
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
          collectionOptions={collectionOptions}
          goal={selectedGoal}
          key={selectedGoal?.id ?? captureHandoff?.id ?? "new-goal"}
          linkOptions={linkOptions}
          onClose={() => {
            setSelectedGoal(undefined);
            setCaptureHandoff(null);
            if (initialGoalId || captureHandoff)
              router.replace("/goals", { scroll: false });
          }}
          ownerId={ownerId}
          sourceCapture={selectedGoal === null ? captureHandoff : null}
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
  const relatedCount = goal.relatedEntries.filter(
    (entry) => entry.relationship === "related",
  ).length;
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
        <div className={styles.goalMeta}>
          <Badge
            size="micro"
            tone={
              goal.status === "active" || goal.status === "achieved"
                ? "accent"
                : "neutral"
            }
            uppercase
          >
            {goalStatusLabels[goal.status]}
          </Badge>
          <Badge size="micro" tone="neutral" uppercase>
            {goalHorizonLabels[goal.horizon]}
          </Badge>
        </div>
        <h3>{goal.title}</h3>
        <p className={styles.target}>{goalTargetLabel(goal)}</p>
        {goal.body ? (
          <p className={styles.reflection}>{truncate(goal.body, 180)}</p>
        ) : null}
        <div className={styles.contextLine}>
          {isBucketListGoal(goal) ? (
            <span>
              <Icon name="star" size={13} /> Bucket List
            </span>
          ) : null}
          {relatedCount > 0 ? (
            <span>{countLabel(relatedCount, "related Item")}</span>
          ) : null}
          {hasAchievement ? <span>First Time linked</span> : null}
        </div>
        <footer>
          <div>
            {goal.collectionNames
              .filter((name) => name.toLocaleLowerCase() !== "bucket list")
              .slice(0, 2)
              .map((name) => (
                <Badge
                  key={`collection:${name.toLocaleLowerCase()}`}
                  size="micro"
                  tone="neutral"
                >
                  {name}
                </Badge>
              ))}
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
  collectionOptions,
  goal,
  linkOptions,
  onClose,
  onTrashed,
  ownerId,
  presentation = "dialog",
  sourceCapture = null,
  tagOptions,
}: {
  collectionOptions: string[];
  goal: GoalRecord | null;
  linkOptions: GoalLinkOption[];
  onClose: () => void;
  onTrashed?: () => void;
  ownerId: string;
  presentation?: "dialog" | "page";
  sourceCapture?: CaptureExtractionSource | null;
  tagOptions: string[];
}) {
  const router = useRouter();
  const requestConfirmation = useConfirmationDialog();
  const titleRef = useRef<HTMLInputElement>(null);
  const [body, setBody] = useState(goal?.body ?? sourceCapture?.body ?? "");
  const [collectionInput, setCollectionInput] = useState("");
  const [collectionNames, setCollectionNames] = useState(
    goal?.collectionNames ?? sourceCapture?.collectionNames ?? [],
  );
  const [currentId, setCurrentId] = useState(goal?.id ?? null);
  const [currentRevision, setCurrentRevision] = useState(
    goal?.revision ?? null,
  );
  const [existingPhotos, setExistingPhotos] = useState(goal?.attachments ?? []);
  const [horizon, setHorizon] = useState<GoalHorizon>(
    goal?.horizon ?? "short_term",
  );
  const [isPending, setIsPending] = useState(false);
  const [photoUploadProgress, setPhotoUploadProgress] =
    useState<PhotoUploadProgressValue | null>(null);
  const [pendingPhotos, setPendingPhotos] = useState<File[]>([]);
  const [relatedEntryIds, setRelatedEntryIds] = useState(
    goal?.relatedEntries
      .filter((entry) => entry.relationship === "related")
      .map((entry) => entry.id) ?? [],
  );
  const [relatedSelection, setRelatedSelection] = useState("");
  const [result, setResult] = useState<GoalActionResult | null>(null);
  const [status, setStatus] = useState<GoalStatus>(
    goal?.status ?? "considering",
  );
  const [tagInput, setTagInput] = useState("");
  const [tagNames, setTagNames] = useState(
    goal?.tagNames ?? sourceCapture?.tagNames ?? [],
  );
  const [targetDate, setTargetDate] = useState(goal?.targetDate ?? "");
  const [title, setTitle] = useState(goal?.title ?? sourceCapture?.title ?? "");
  const captureReference = pendingCaptureReference(sourceCapture, currentId);

  useEffect(() => {
    titleRef.current?.focus();
  }, []);

  const selectableEntries = useMemo(
    () =>
      linkOptions.filter(
        (entry) =>
          entry.id !== currentId && !relatedEntryIds.includes(entry.id),
      ),
    [currentId, linkOptions, relatedEntryIds],
  );
  const selectedEntries = relatedEntryIds.map((id) => {
    const option = linkOptions.find((entry) => entry.id === id);
    const existing = goal?.relatedEntries.find((entry) => entry.id === id);
    return {
      id,
      title: option?.title ?? existing?.title ?? "Related Item",
    };
  });
  const savedBucketListGoal = Boolean(
    goal && isBucketListGoal(goal) && status !== "achieved",
  );
  const hasUnsavedChanges = Boolean(
    goal &&
    (title !== goal.title ||
      body !== goal.body ||
      horizon !== goal.horizon ||
      status !== goal.status ||
      (targetDate || null) !== goal.targetDate ||
      !sameNames(collectionNames, goal.collectionNames) ||
      !sameNames(tagNames, goal.tagNames) ||
      !sameNames(
        relatedEntryIds,
        goal.relatedEntries
          .filter((entry) => entry.relationship === "related")
          .map((entry) => entry.id),
      ) ||
      Boolean(collectionInput.trim()) ||
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
      errorMessage = `Keep up to ${firstTimePhotoLimit} photos on a Goal.`;
    }
    setPendingPhotos((current) => [...current, ...accepted]);
    setResult(errorMessage ? actionError(errorMessage) : null);
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const input: GoalEntryInput = {
      body,
      collectionNames: namesIncludingDraft(collectionNames, collectionInput),
      horizon,
      id: currentId,
      relatedEntryIds,
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
      const saved = await saveGoalEntry(parsed.data, captureReference);
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
            `The Goal was saved, but ${countLabel(failedPhotos.length, "photo")} could not be attached. Select Save again to retry.`,
          ),
        );
        router.refresh();
        return;
      }
      router.refresh();
      notify.success(
        saved.status === "created" ? "Goal created." : "Goal saved.",
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
      title: <>Move “{title.trim() || "this Goal"}” to Trash?</>,
      description: <>Its history and private photos will be preserved.</>,
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
        notify.info("Goal moved to Trash.");
      } else {
        setResult(nextResult);
      }
    } catch {
      setResult(actionError("MemoTrail could not move this Goal to Trash."));
    } finally {
      setIsPending(false);
    }
  }

  return (
    <FocusedEditorSurface
      onClose={onClose}
      presentation={presentation}
      title={
        <>
          {currentId
            ? title || "Goal"
            : sourceCapture
              ? "Create a Goal from this Capture"
              : "Keep an intention close"}
        </>
      }
      titleId="goal-editor-title"
      eyebrow={<>{currentId ? "Edit Goal" : "New Goal"}</>}
      closeLabel="Close Goal editor"
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
                  : "Add Goal"}
            </Button>
          </div>
        </div>
      }
    >
      {" "}
      <form id="goals-workspace-form" onSubmit={handleSubmit}>
        <div className={common.formGrid}>
          {captureReference ? (
            <div className={common.extractionNotice}>
              <Icon name="inbox" size={18} />
              <div>
                <strong>Starting from an Inbox Capture</strong>
                <p>
                  Saving creates a separate Goal and links it to the preserved
                  source Capture.
                </p>
              </div>
            </div>
          ) : null}
          <fieldset className={common.formSection}>
            <legend>The intention</legend>
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
            <label>
              <span>Horizon</span>
              <select
                onChange={(event) =>
                  setHorizon(event.target.value as GoalHorizon)
                }
                value={horizon}
              >
                {goalHorizons.map((value) => (
                  <option key={value} value={value}>
                    {goalHorizonLabels[value]}
                  </option>
                ))}
              </select>
            </label>
            <label>
              <span>Reflective state</span>
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
            <DatePickerField
              disabled={isPending}
              label="Target date"
              onChange={setTargetDate}
              value={targetDate}
            />
            <label className={common.fullField}>
              <span>Reflection</span>
              <textarea
                maxLength={goalBodyLimit}
                onChange={(event) => setBody(event.target.value)}
                placeholder="Why does this matter? What would you like to remember about wanting it?"
                rows={6}
                value={body}
              />
            </label>
          </fieldset>

          <fieldset className={common.formSection}>
            <legend>Organization</legend>
            <EntryOrganizationEditor
              disabled={isPending}
              input={collectionInput}
              kind="collection"
              names={collectionNames}
              onChange={setCollectionNames}
              onInputChange={setCollectionInput}
              options={collectionOptions}
            />
            <EntryOrganizationEditor
              disabled={isPending}
              input={tagInput}
              kind="tag"
              names={tagNames}
              onChange={setTagNames}
              onInputChange={setTagInput}
              options={tagOptions}
            />
          </fieldset>

          <fieldset
            className={`${common.formSection} ${styles.relatedSection}`}
          >
            <legend>Related Items</legend>
            <p>
              Link memories, ideas, or learning that give this Goal context.
            </p>
            {selectedEntries.length > 0 ? (
              <div className={styles.relatedChips}>
                {selectedEntries.map((entry) => (
                  <Button
                    variant="secondary"
                    aria-label={`Remove related Item ${entry.title}`}
                    disabled={isPending}
                    key={entry.id}
                    onClick={() =>
                      setRelatedEntryIds((current) =>
                        current.filter((id) => id !== entry.id),
                      )
                    }
                    type="button"
                  >
                    {entry.title}
                    <span aria-hidden="true">×</span>
                  </Button>
                ))}
              </div>
            ) : null}
            <div className={styles.relatedPicker}>
              <select
                aria-label="Choose a related Item"
                disabled={isPending || selectableEntries.length === 0}
                onChange={(event) => setRelatedSelection(event.target.value)}
                value={relatedSelection}
              >
                <option value="">
                  {selectableEntries.length > 0
                    ? "Choose an Item"
                    : "No more Items available"}
                </option>
                {selectableEntries.map((entry) => (
                  <option key={entry.id} value={entry.id}>
                    {entry.title} ·{" "}
                    {wikiItemIdentityLabel(entry.itemKind, entry.itemSubtype)}
                  </option>
                ))}
              </select>
              <Button
                variant="secondary"
                disabled={!relatedSelection || isPending}
                onClick={() => {
                  setRelatedEntryIds((current) => [
                    ...current,
                    relatedSelection,
                  ]);
                  setRelatedSelection("");
                }}
                type="button"
              >
                Add link
              </Button>
            </div>
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
            recordLabel="Goal"
          />

          {savedBucketListGoal && currentId && currentRevision !== null ? (
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
      <legend>Bucket List milestone</legend>
      <div className={styles.achievementIntro}>
        <span>
          <Icon name="star" size={18} />
        </span>
        <div>
          <strong>Turn this achievement into a First Time</strong>
          <p>
            MemoTrail will mark the Goal Achieved and create a linked First Time
            with the same title. Your private reflection stays here.
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
          Save your other Goal changes before recording this milestone.
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
        Mark achieved and create First Time
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
