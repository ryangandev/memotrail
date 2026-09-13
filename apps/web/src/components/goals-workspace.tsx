"use client";

import {
  useEffect,
  useMemo,
  useRef,
  useState,
  type ChangeEvent,
  type FormEvent,
} from "react";
import { useRouter } from "next/navigation";
import {
  markGoalAchieved,
  registerGoalAttachment,
  saveGoalEntry,
  trashGoalAttachment,
  trashGoalEntry,
  type GoalActionResult,
} from "@/app/goals/actions";
import styles from "@/app/goals/page.module.css";
import common from "@/app/homes/page.module.css";
import { Icon } from "@/components/icon";
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
import { uploadEntryPhotos } from "@/lib/media/upload";

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
  tagOptions,
}: {
  collectionOptions: string[];
  goals: GoalRecord[];
  initialGoalId: string | null;
  linkOptions: GoalLinkOption[];
  loadError: string | null;
  ownerId: string;
  tagOptions: string[];
}) {
  const router = useRouter();
  const [selectedGoal, setSelectedGoal] = useState<
    GoalRecord | null | undefined
  >(goals.find((goal) => goal.id === initialGoalId));
  const openCount = goals.filter(
    (goal) => !["achieved", "let_go"].includes(goal.status),
  ).length;
  const bucketCount = goals.filter(isBucketListGoal).length;

  return (
    <div className={common.content}>
      <header className={common.pageHeader}>
        <div>
          <p className={common.eyebrow}>Intentions without pressure</p>
          <h1>Goals</h1>
          <p>
            Keep near-term plans, distant hopes, and someday ideas together as
            part of your personal archive.
          </p>
        </div>
        <button
          aria-label="Add Goal"
          className={common.addButton}
          onClick={() => setSelectedGoal(null)}
          type="button"
        >
          <Icon name="plus" />
          <span>Add Goal</span>
        </button>
      </header>

      <div className={common.summary} aria-label="Goals summary">
        <span>{countLabel(goals.length, "goal")}</span>
        <span aria-hidden="true">·</span>
        <span>{openCount} open</span>
        <span aria-hidden="true">·</span>
        <span>{bucketCount} in Bucket List</span>
      </div>

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
        <button
          className={common.emptyState}
          onClick={() => setSelectedGoal(null)}
          type="button"
        >
          <span className={common.emptyMark}>
            <Icon name="sparkle" size={24} />
          </span>
          <strong>Keep one possibility close</strong>
          <span>
            Give it a name now. Its horizon, context, and meaning can evolve
            with you.
          </span>
        </button>
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
                onSelect={setSelectedGoal}
                title={section.title}
              />
            ) : null;
          })
        : null}

      {selectedGoal !== undefined ? (
        <GoalEditor
          collectionOptions={collectionOptions}
          goal={selectedGoal}
          key={selectedGoal?.id ?? "new-goal"}
          linkOptions={linkOptions}
          onClose={() => {
            setSelectedGoal(undefined);
            if (initialGoalId) router.replace("/goals", { scroll: false });
          }}
          ownerId={ownerId}
          tagOptions={tagOptions}
        />
      ) : null}
    </div>
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
    <button
      aria-label={`${goal.title}, ${goalStatusLabels[goal.status]}`}
      className={styles.goalCard}
      onClick={onSelect}
      type="button"
    >
      {cover?.imageUrl ? (
        <div className={styles.goalCover}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img alt="" src={cover.imageUrl} />
          {goal.attachments.length > 1 ? (
            <span>{goal.attachments.length} photos</span>
          ) : null}
        </div>
      ) : null}
      <div className={styles.goalCardBody}>
        <div className={styles.goalMeta}>
          <span data-status={goal.status}>{goalStatusLabels[goal.status]}</span>
          <span>{goalHorizonLabels[goal.horizon]}</span>
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
            <span>{countLabel(relatedCount, "related Entry")}</span>
          ) : null}
          {hasAchievement ? <span>First Time linked</span> : null}
        </div>
        <footer>
          <div>
            {goal.collectionNames
              .filter((name) => name.toLocaleLowerCase() !== "bucket list")
              .slice(0, 2)
              .map((name) => (
                <span key={`collection:${name.toLocaleLowerCase()}`}>
                  {name}
                </span>
              ))}
            {goal.tagNames.slice(0, 2).map((name) => (
              <span key={`tag:${name.toLocaleLowerCase()}`}>#{name}</span>
            ))}
          </div>
          <Icon name="chevron" size={15} />
        </footer>
      </div>
    </button>
  );
}

function GoalEditor({
  collectionOptions,
  goal,
  linkOptions,
  onClose,
  ownerId,
  tagOptions,
}: {
  collectionOptions: string[];
  goal: GoalRecord | null;
  linkOptions: GoalLinkOption[];
  onClose: () => void;
  ownerId: string;
  tagOptions: string[];
}) {
  const router = useRouter();
  const titleRef = useRef<HTMLInputElement>(null);
  const [body, setBody] = useState(goal?.body ?? "");
  const [collectionInput, setCollectionInput] = useState("");
  const [collectionNames, setCollectionNames] = useState(
    goal?.collectionNames ?? [],
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
  const [tagNames, setTagNames] = useState(goal?.tagNames ?? []);
  const [targetDate, setTargetDate] = useState(goal?.targetDate ?? "");
  const [title, setTitle] = useState(goal?.title ?? "");

  useEffect(() => {
    titleRef.current?.focus();
  }, []);

  useEffect(() => {
    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape" && !isPending) onClose();
    }
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [isPending, onClose]);

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
      title: option?.title ?? existing?.title ?? "Related Entry",
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

  function handlePhotoSelection(event: ChangeEvent<HTMLInputElement>) {
    const selected = Array.from(event.target.files ?? []);
    event.target.value = "";
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
      onClose();
    } catch {
      setResult(
        actionError(
          "MemoTrail could not reach the server. Try again when online.",
        ),
      );
    } finally {
      setIsPending(false);
    }
  }

  async function handleRemovePhoto(photo: GoalAttachment) {
    if (
      !window.confirm(
        "Move this photo to Trash? The original will be preserved.",
      )
    ) {
      return;
    }
    setIsPending(true);
    setResult(null);
    try {
      const nextResult = await trashGoalAttachment({ attachmentId: photo.id });
      if (nextResult.status === "trashed") {
        setExistingPhotos((current) =>
          current.filter((item) => item.id !== photo.id),
        );
        router.refresh();
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
    if (
      !currentId ||
      currentRevision === null ||
      !window.confirm(
        `Move “${title.trim() || "this Goal"}” to Trash? Its history and private photos will be preserved.`,
      )
    ) {
      return;
    }
    setIsPending(true);
    setResult(null);
    try {
      const nextResult = await trashGoalEntry({
        id: currentId,
        revision: currentRevision,
      });
      if (nextResult.status === "trashed") {
        router.refresh();
        onClose();
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
    <div
      aria-labelledby="goal-editor-title"
      aria-modal="true"
      className={common.dialogBackdrop}
      onMouseDown={(event) => {
        if (event.currentTarget === event.target && !isPending) onClose();
      }}
      role="dialog"
    >
      <div className={common.dialogPanel}>
        <header className={common.dialogHeader}>
          <div>
            <p>{currentId ? "Edit Goal" : "New Goal"}</p>
            <h2 id="goal-editor-title">
              {currentId ? title || "Goal" : "Keep an intention close"}
            </h2>
          </div>
          <button
            aria-label="Close Goal editor"
            disabled={isPending}
            onClick={onClose}
            type="button"
          >
            ×
          </button>
        </header>

        <form onSubmit={handleSubmit}>
          <div className={common.formGrid}>
            <fieldset className={common.formSection}>
              <legend>The intention</legend>
              <label className={common.fullField}>
                <span>Title</span>
                <input
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
              <label>
                <span>
                  Target date <small>Optional, no overdue state</small>
                </span>
                <input
                  onChange={(event) => setTargetDate(event.target.value)}
                  type="date"
                  value={targetDate}
                />
              </label>
              <label className={common.fullField}>
                <span>
                  Reflection <small>Optional</small>
                </span>
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
              <OrganizationEditor
                disabled={isPending}
                input={collectionInput}
                label="Collections"
                maximumCount={20}
                maximumNameLength={80}
                names={collectionNames}
                onChange={setCollectionNames}
                onInputChange={setCollectionInput}
                options={collectionOptions}
                placeholder="Add a Collection"
              />
              <OrganizationEditor
                disabled={isPending}
                input={tagInput}
                label="Tags"
                maximumCount={50}
                maximumNameLength={60}
                names={tagNames}
                onChange={setTagNames}
                onInputChange={setTagInput}
                options={tagOptions}
                placeholder="Add a tag"
              />
            </fieldset>

            <fieldset
              className={`${common.formSection} ${styles.relatedSection}`}
            >
              <legend>Related Entries</legend>
              <p>
                Link memories, ideas, or learning that give this Goal context.
              </p>
              {selectedEntries.length > 0 ? (
                <div className={styles.relatedChips}>
                  {selectedEntries.map((entry) => (
                    <button
                      aria-label={`Remove related Entry ${entry.title}`}
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
                    </button>
                  ))}
                </div>
              ) : null}
              <div className={styles.relatedPicker}>
                <select
                  aria-label="Choose a related Entry"
                  disabled={isPending || selectableEntries.length === 0}
                  onChange={(event) => setRelatedSelection(event.target.value)}
                  value={relatedSelection}
                >
                  <option value="">
                    {selectableEntries.length > 0
                      ? "Choose an Entry"
                      : "No more Entries available"}
                  </option>
                  {selectableEntries.map((entry) => (
                    <option key={entry.id} value={entry.id}>
                      {entry.title} · {entryTypeLabel(entry.entryType)}
                    </option>
                  ))}
                </select>
                <button
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
                </button>
              </div>
            </fieldset>

            <fieldset className={`${common.photoField} ${common.formSection}`}>
              <legend>Photos</legend>
              {existingPhotos.length > 0 || pendingPhotos.length > 0 ? (
                <div className={common.photoGrid}>
                  {existingPhotos.map((photo) => (
                    <div className={common.photoTile} key={photo.id}>
                      {photo.imageUrl ? (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img
                          alt={photo.originalFilename ?? "Goal photo"}
                          src={photo.imageUrl}
                        />
                      ) : (
                        <span className={common.photoFallback}>
                          Private photo
                        </span>
                      )}
                      <button
                        aria-label={`Remove ${photo.originalFilename ?? "photo"}`}
                        disabled={isPending}
                        onClick={() => void handleRemovePhoto(photo)}
                        type="button"
                      >
                        ×
                      </button>
                    </div>
                  ))}
                  {pendingPhotos.map((file, index) => (
                    <PendingPhoto
                      file={file}
                      key={`${file.name}:${file.size}:${file.lastModified}:${index}`}
                      onRemove={() =>
                        setPendingPhotos((current) =>
                          current.filter((_, itemIndex) => itemIndex !== index),
                        )
                      }
                    />
                  ))}
                </div>
              ) : null}
              <label className={common.photoPicker}>
                <Icon name="photo" size={18} />
                <span>Add photos</span>
                <input
                  accept="image/jpeg,image/png,image/webp,image/heic,image/heif,.heic,.heif"
                  disabled={
                    isPending ||
                    existingPhotos.length + pendingPhotos.length >=
                      firstTimePhotoLimit
                  }
                  multiple
                  onChange={handlePhotoSelection}
                  type="file"
                />
              </label>
              <small>
                Originals stay private. Up to {firstTimePhotoLimit} photos, 50
                MB each.
              </small>
            </fieldset>

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
                  setResult(nextResult);
                  router.refresh();
                }}
                onPendingChange={setIsPending}
              />
            ) : null}
          </div>

          {result ? (
            <p
              className={`${common.formMessage} ${result.status === "achieved" ? styles.successMessage : ""}`}
              role="status"
            >
              {result.message}
            </p>
          ) : null}

          <footer className={common.dialogFooter}>
            <div>
              {currentId ? (
                <button
                  className={common.trashButton}
                  disabled={isPending}
                  onClick={() => void handleTrashEntry()}
                  type="button"
                >
                  Move to Trash
                </button>
              ) : null}
            </div>
            <div>
              <button
                className={common.cancelButton}
                disabled={isPending}
                onClick={onClose}
                type="button"
              >
                Cancel
              </button>
              <button
                className={common.saveButton}
                disabled={isPending}
                type="submit"
              >
                {isPending
                  ? "Saving..."
                  : currentId
                    ? "Save changes"
                    : "Add Goal"}
              </button>
            </div>
          </footer>
        </form>
      </div>
    </div>
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
      <button
        className={styles.achievementButton}
        disabled={disabled || unsavedChanges}
        onClick={() => void handleAchievement()}
        type="button"
      >
        <Icon name="check" size={16} />
        Mark achieved and create First Time
      </button>
    </fieldset>
  );
}

function OrganizationEditor({
  disabled,
  input,
  label,
  maximumCount,
  maximumNameLength,
  names,
  onChange,
  onInputChange,
  options,
  placeholder,
}: {
  disabled: boolean;
  input: string;
  label: string;
  maximumCount: number;
  maximumNameLength: number;
  names: string[];
  onChange: (names: string[]) => void;
  onInputChange: (input: string) => void;
  options: string[];
  placeholder: string;
}) {
  const datalistId = `goal-${label.toLocaleLowerCase()}-options`;
  const normalizedNames = new Set(
    names.map((name) => name.toLocaleLowerCase()),
  );

  function addName(value: string) {
    const name = value.trim();
    if (
      !name ||
      name.length > maximumNameLength ||
      names.length >= maximumCount ||
      normalizedNames.has(name.toLocaleLowerCase())
    ) {
      onInputChange("");
      return;
    }
    onChange([...names, name]);
    onInputChange("");
  }

  return (
    <fieldset className={common.organizationEditor} disabled={disabled}>
      <legend>{label}</legend>
      {names.length > 0 ? (
        <div className={common.organizationChips}>
          {names.map((name) => (
            <button
              aria-label={`Remove ${name} from ${label}`}
              key={name.toLocaleLowerCase()}
              onClick={() => onChange(names.filter((item) => item !== name))}
              type="button"
            >
              {name}
              <span aria-hidden="true">×</span>
            </button>
          ))}
        </div>
      ) : null}
      <input
        list={datalistId}
        maxLength={maximumNameLength}
        onChange={(event) => onInputChange(event.target.value)}
        onKeyDown={(event) => {
          if (event.key === "Enter") {
            event.preventDefault();
            addName(input);
          }
        }}
        placeholder={`${placeholder} and press Enter`}
        value={input}
      />
      <datalist id={datalistId}>
        {options
          .filter((option) => !normalizedNames.has(option.toLocaleLowerCase()))
          .map((option) => (
            <option key={option.toLocaleLowerCase()} value={option} />
          ))}
      </datalist>
      <small>
        {names.length} of {maximumCount}
      </small>
    </fieldset>
  );
}

function PendingPhoto({
  file,
  onRemove,
}: {
  file: File;
  onRemove: () => void;
}) {
  const [previewUrl] = useState(() => URL.createObjectURL(file));
  useEffect(() => () => URL.revokeObjectURL(previewUrl), [previewUrl]);
  return (
    <div className={`${common.photoTile} ${common.pendingPhoto}`}>
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img alt={`Selected ${file.name}`} src={previewUrl} />
      <span>New</span>
      <button
        aria-label={`Remove selected ${file.name}`}
        onClick={onRemove}
        type="button"
      >
        ×
      </button>
    </div>
  );
}

async function uploadPhotos(ownerId: string, entryId: string, photos: File[]) {
  return uploadEntryPhotos(ownerId, entryId, photos, registerGoalAttachment);
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

function entryTypeLabel(value: string) {
  return value
    .replaceAll("_", " ")
    .replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function actionError(message: string): GoalActionResult {
  return {
    entry: null,
    firstTimeEntryId: null,
    message,
    status: "error",
  };
}

function countLabel(count: number, singular: string) {
  return `${count} ${count === 1 ? singular : `${singular}s`}`;
}

function truncate(value: string, limit: number) {
  return value.length > limit ? `${value.slice(0, limit).trimEnd()}...` : value;
}
