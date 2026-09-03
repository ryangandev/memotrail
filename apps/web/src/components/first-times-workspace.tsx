"use client";

import {
  useEffect,
  useRef,
  useState,
  type ChangeEvent,
  type FormEvent,
} from "react";
import { useRouter } from "next/navigation";
import {
  registerFirstTimeAttachment,
  saveFirstTimeEntry,
  trashFirstTimeAttachment,
  trashFirstTimeEntry,
  type FirstTimeActionResult,
} from "@/app/first-times/actions";
import styles from "@/app/first-times/page.module.css";
import { Icon } from "@/components/icon";
import {
  createFirstTimeObjectPath,
  firstTimeBodyLimit,
  firstTimeLabelLimit,
  firstTimePhotoLimit,
  firstTimePhotoSizeLimit,
  firstTimeTitleLimit,
  inferFirstTimeImageMimeType,
  parseFirstTimeEntryInput,
  type FirstTimeDatePrecision,
  type FirstTimeEntryInput,
} from "@/lib/data/first-time-input";
import type {
  FirstTimeAttachment,
  FirstTimeEntry,
} from "@/lib/data/first-times";
import {
  localDateToISOString,
  localDateValue,
} from "@/lib/data/timeline-input";
import { createClient } from "@/lib/supabase/client";

const precisionOptions: {
  label: string;
  value: FirstTimeDatePrecision;
}[] = [
  { label: "Exact day", value: "day" },
  { label: "Month and year", value: "month" },
  { label: "Year", value: "year" },
  { label: "Approximate", value: "approximate" },
  { label: "Age-based", value: "age" },
  { label: "Unknown", value: "unknown" },
];

export function FirstTimesWorkspace({
  collectionOptions,
  entries,
  loadError,
  ownerId,
  tagOptions,
}: {
  collectionOptions: string[];
  entries: FirstTimeEntry[];
  loadError: string | null;
  ownerId: string;
  tagOptions: string[];
}) {
  const [selectedEntry, setSelectedEntry] = useState<FirstTimeEntry | null>();
  const photoCount = entries.reduce(
    (count, entry) => count + originalAttachments(entry).length,
    0,
  );

  return (
    <div className={styles.content}>
      <header className={styles.pageHeader}>
        <div>
          <p className={styles.eyebrow}>A record of beginnings</p>
          <h1>First Times</h1>
          <p>
            Keep the small beginnings and major milestones worth finding again.
          </p>
        </div>
        <button
          aria-label="Add First Time"
          className={styles.addButton}
          onClick={() => setSelectedEntry(null)}
          type="button"
        >
          <Icon name="plus" />
          <span>Add First Time</span>
        </button>
      </header>

      <div className={styles.summary} aria-label="First Times summary">
        <span>{countLabel(entries.length, "First Time")}</span>
        <span aria-hidden="true">·</span>
        <span>{countLabel(photoCount, "photo")}</span>
      </div>

      {loadError ? (
        <div className={styles.message} role="alert">
          <Icon name="star" size={22} />
          <div>
            <strong>First Times unavailable</strong>
            <p>{loadError}</p>
          </div>
        </div>
      ) : null}

      {!loadError && entries.length === 0 ? (
        <button
          className={styles.emptyState}
          onClick={() => setSelectedEntry(null)}
          type="button"
        >
          <span className={styles.emptyMark}>
            <Icon name="star" size={24} />
          </span>
          <strong>Start with a first worth remembering</strong>
          <span>
            Only a title is required. Dates, notes, and photos can come later.
          </span>
        </button>
      ) : null}

      {!loadError && entries.length > 0 ? (
        <section className={styles.firstGrid} aria-label="First Times archive">
          {entries.map((entry, index) => (
            <FirstTimeCard
              entry={entry}
              index={index}
              key={entry.id}
              onSelect={() => setSelectedEntry(entry)}
            />
          ))}
        </section>
      ) : null}

      {selectedEntry !== undefined ? (
        <FirstTimeEditor
          collectionOptions={collectionOptions}
          entry={selectedEntry}
          key={selectedEntry?.id ?? "new-first-time"}
          onClose={() => setSelectedEntry(undefined)}
          ownerId={ownerId}
          tagOptions={tagOptions}
        />
      ) : null}
    </div>
  );
}

function FirstTimeCard({
  entry,
  index,
  onSelect,
}: {
  entry: FirstTimeEntry;
  index: number;
  onSelect: () => void;
}) {
  const photos = originalAttachments(entry);
  const cover = photos[0];

  return (
    <button
      aria-label={`${entry.title}, ${firstTimeDateLabel(entry)}`}
      className={styles.firstCard}
      onClick={onSelect}
      type="button"
    >
      {cover ? (
        <div className={styles.coverPhoto}>
          {cover.imageUrl ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img alt="" src={cover.imageUrl} />
          ) : (
            <span>
              <Icon name="photo" size={22} />
              Private photo
            </span>
          )}
          {photos.length > 1 ? <small>{photos.length} photos</small> : null}
        </div>
      ) : (
        <div className={styles.cardIndex} aria-hidden="true">
          {String(index + 1).padStart(2, "0")}
        </div>
      )}

      <div className={styles.cardBody}>
        <time dateTime={entry.occurredStart ?? undefined}>
          {firstTimeDateLabel(entry)}
        </time>
        <h2>{entry.title}</h2>
        {entry.body ? <p>{truncate(entry.body, 180)}</p> : null}
        <footer>
          <div>
            {entry.inboxStatus === "unreviewed" ? <span>In Inbox</span> : null}
            {entry.collectionNames.slice(0, 2).map((name) => (
              <span key={`collection:${name.toLocaleLowerCase()}`}>{name}</span>
            ))}
            {entry.tagNames.slice(0, 2).map((name) => (
              <span key={`tag:${name.toLocaleLowerCase()}`}>#{name}</span>
            ))}
          </div>
          <Icon name="chevron" size={15} />
        </footer>
      </div>
    </button>
  );
}

function FirstTimeEditor({
  collectionOptions,
  entry,
  onClose,
  ownerId,
  tagOptions,
}: {
  collectionOptions: string[];
  entry: FirstTimeEntry | null;
  onClose: () => void;
  ownerId: string;
  tagOptions: string[];
}) {
  const router = useRouter();
  const titleRef = useRef<HTMLInputElement>(null);
  const initialTimezone = entry?.occurredTimezone ?? localTimezone();
  const [body, setBody] = useState(entry?.body ?? "");
  const [collectionInput, setCollectionInput] = useState("");
  const [collectionNames, setCollectionNames] = useState(
    entry?.collectionNames ?? [],
  );
  const [currentId, setCurrentId] = useState(entry?.id ?? null);
  const [currentRevision, setCurrentRevision] = useState(
    entry?.revision ?? null,
  );
  const [datePrecision, setDatePrecision] = useState<FirstTimeDatePrecision>(
    editablePrecision(entry?.datePrecision),
  );
  const [existingPhotos, setExistingPhotos] = useState(
    entry ? originalAttachments(entry) : [],
  );
  const [isPending, setIsPending] = useState(false);
  const [occurredDate, setOccurredDate] = useState(
    entry?.occurredStart
      ? localDateValue(entry.occurredStart, initialTimezone)
      : "",
  );
  const [occurredLabel, setOccurredLabel] = useState(
    entry?.occurredLabel ?? "",
  );
  const [occurredTimezone, setOccurredTimezone] = useState(
    entry?.occurredTimezone ?? null,
  );
  const [pendingPhotos, setPendingPhotos] = useState<File[]>([]);
  const [result, setResult] = useState<FirstTimeActionResult | null>(null);
  const [tagInput, setTagInput] = useState("");
  const [tagNames, setTagNames] = useState(entry?.tagNames ?? []);
  const [title, setTitle] = useState(entry?.title ?? "");

  useEffect(() => {
    titleRef.current?.focus();

    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape" && !isPending) {
        onClose();
      }
    }

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [isPending, onClose]);

  function handlePhotoSelection(event: ChangeEvent<HTMLInputElement>) {
    const selected = Array.from(event.target.files ?? []);
    event.target.value = "";

    if (selected.length === 0) {
      return;
    }

    const available = Math.max(
      0,
      firstTimePhotoLimit - existingPhotos.length - pendingPhotos.length,
    );
    const accepted: File[] = [];
    let errorMessage = "";

    for (const file of selected.slice(0, available)) {
      if (!inferFirstTimeImageMimeType(file.name, file.type)) {
        errorMessage = "Use JPEG, PNG, WebP, HEIC, or HEIF photos.";
        continue;
      }

      if (file.size < 1 || file.size > firstTimePhotoSizeLimit) {
        errorMessage = "Each photo must be no larger than 50 MB.";
        continue;
      }

      accepted.push(file);
    }

    if (selected.length > available) {
      errorMessage = `Keep up to ${firstTimePhotoLimit} photos on a First Time.`;
    }

    setPendingPhotos((current) => [...current, ...accepted]);
    setResult(errorMessage ? actionError(errorMessage) : null);
  }

  function handleDateChange(value: string) {
    setOccurredDate(value);

    if (value) {
      setOccurredTimezone(localTimezone());
      if (datePrecision === "unknown") {
        setDatePrecision("day");
      }
    } else {
      setOccurredTimezone(null);
      if (!["age", "approximate"].includes(datePrecision)) {
        setDatePrecision("unknown");
      }
    }
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const occurredStart = occurredDate
      ? localDateToISOString(occurredDate, occurredTimezone ?? localTimezone())
      : null;
    const input: FirstTimeEntryInput = {
      body,
      collectionNames: namesIncludingDraft(collectionNames, collectionInput),
      datePrecision,
      id: currentId,
      occurredLabel: occurredLabel || null,
      occurredStart: occurredStart ?? (occurredDate || null),
      occurredTimezone: occurredDate
        ? (occurredTimezone ?? localTimezone())
        : null,
      revision: currentRevision,
      tagNames: namesIncludingDraft(tagNames, tagInput),
      title,
    };
    const parsed = parseFirstTimeEntryInput(input);

    if (!parsed.success) {
      setResult(actionError(parsed.message));
      return;
    }

    setIsPending(true);
    setResult(null);

    try {
      const saved = await saveFirstTimeEntry(parsed.data);

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
            `The First Time was saved, but ${countLabel(failedPhotos.length, "photo")} could not be attached. Select Save again to retry.`,
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

  async function handleRemovePhoto(photo: FirstTimeAttachment) {
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
      const nextResult = await trashFirstTimeAttachment({
        attachmentId: photo.id,
      });

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
        `Move “${title.trim() || "this First Time"}” to Trash? Its history and private photos will be preserved.`,
      )
    ) {
      return;
    }

    setIsPending(true);
    setResult(null);

    try {
      const nextResult = await trashFirstTimeEntry({
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
      setResult(
        actionError("MemoTrail could not move this First Time to Trash."),
      );
    } finally {
      setIsPending(false);
    }
  }

  return (
    <div
      aria-labelledby="first-time-editor-title"
      aria-modal="true"
      className={styles.dialogBackdrop}
      onMouseDown={(event) => {
        if (event.currentTarget === event.target && !isPending) {
          onClose();
        }
      }}
      role="dialog"
    >
      <div className={styles.dialogPanel}>
        <header className={styles.dialogHeader}>
          <div>
            <p>{currentId ? "Edit First Time" : "New First Time"}</p>
            <h2 id="first-time-editor-title">
              {currentId ? title || "First Time" : "Keep a beginning"}
            </h2>
          </div>
          <button
            aria-label="Close First Time editor"
            disabled={isPending}
            onClick={onClose}
            type="button"
          >
            ×
          </button>
        </header>

        <form onSubmit={handleSubmit}>
          <div className={styles.formGrid}>
            <label className={styles.fullField}>
              <span>Title</span>
              <input
                maxLength={firstTimeTitleLimit}
                onChange={(event) => setTitle(event.target.value)}
                placeholder="First time skiing"
                ref={titleRef}
                value={title}
              />
            </label>

            <label>
              <span>
                Date <small>Optional</small>
              </span>
              <input
                onChange={(event) => handleDateChange(event.target.value)}
                type="date"
                value={occurredDate}
              />
            </label>

            <label>
              <span>Date precision</span>
              <select
                onChange={(event) =>
                  setDatePrecision(event.target.value as FirstTimeDatePrecision)
                }
                value={datePrecision}
              >
                {precisionOptions.map((option) => (
                  <option key={option.value} value={option.value}>
                    {option.label}
                  </option>
                ))}
              </select>
            </label>

            <label className={styles.fullField}>
              <span>
                Human date label <small>Optional</small>
              </span>
              <input
                maxLength={firstTimeLabelLimit}
                onChange={(event) => setOccurredLabel(event.target.value)}
                placeholder="For example: Age 17 or Summer 2017"
                value={occurredLabel}
              />
              <small>
                Use this when the remembered wording matters more than
                precision.
              </small>
            </label>

            <label className={styles.fullField}>
              <span>
                Reflection <small>Optional</small>
              </span>
              <textarea
                maxLength={firstTimeBodyLimit}
                onChange={(event) => setBody(event.target.value)}
                placeholder="What happened, and what do you want to remember?"
                rows={5}
                value={body}
              />
            </label>

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

            <fieldset className={`${styles.photoField} ${styles.fullField}`}>
              <legend>Photos</legend>
              {existingPhotos.length > 0 || pendingPhotos.length > 0 ? (
                <div className={styles.photoGrid}>
                  {existingPhotos.map((photo) => (
                    <div className={styles.photoTile} key={photo.id}>
                      {photo.imageUrl ? (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img
                          alt={photo.originalFilename ?? "First Time photo"}
                          src={photo.imageUrl}
                        />
                      ) : (
                        <span className={styles.photoFallback}>
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
              <label className={styles.photoPicker}>
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
          </div>

          {result ? (
            <p className={styles.formMessage} role="alert">
              {result.message}
            </p>
          ) : null}

          <footer className={styles.dialogFooter}>
            <div>
              {currentId ? (
                <button
                  className={styles.trashButton}
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
                className={styles.cancelButton}
                disabled={isPending}
                onClick={onClose}
                type="button"
              >
                Cancel
              </button>
              <button
                className={styles.saveButton}
                disabled={isPending}
                type="submit"
              >
                {isPending
                  ? "Saving..."
                  : currentId
                    ? "Save changes"
                    : "Add First Time"}
              </button>
            </div>
          </footer>
        </form>
      </div>
    </div>
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
  const datalistId = `first-time-${label.toLocaleLowerCase()}-options`;
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
    <fieldset className={styles.organizationEditor} disabled={disabled}>
      <legend>{label}</legend>
      {names.length > 0 ? (
        <div className={styles.organizationChips}>
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

  useEffect(() => {
    return () => URL.revokeObjectURL(previewUrl);
  }, [previewUrl]);

  return (
    <div className={`${styles.photoTile} ${styles.pendingPhoto}`}>
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
  const failed: File[] = [];
  const client = createClient();

  for (const photo of photos) {
    const mimeType = inferFirstTimeImageMimeType(photo.name, photo.type);
    const attachmentId = crypto.randomUUID();
    const objectPath = mimeType
      ? createFirstTimeObjectPath(ownerId, entryId, attachmentId, mimeType)
      : null;

    if (!mimeType || !objectPath) {
      failed.push(photo);
      continue;
    }

    const upload = await client.storage
      .from("entry-media")
      .upload(objectPath, photo, {
        cacheControl: "3600",
        contentType: mimeType,
        upsert: false,
      });

    if (upload.error) {
      console.warn("First Time photo upload failed:", upload.error.message);
      failed.push(photo);
      continue;
    }

    const registered = await registerFirstTimeAttachment({
      attachmentId,
      byteSize: photo.size,
      entryId,
      mimeType,
      objectPath,
      originalFilename: photo.name || null,
      pixelHeight: null,
      pixelWidth: null,
    });

    if (registered.status !== "saved") {
      console.warn("First Time photo registration failed:", registered.message);
      await client.storage.from("entry-media").remove([objectPath]);
      failed.push(photo);
    }
  }

  return failed;
}

function originalAttachments(entry: FirstTimeEntry) {
  return entry.attachments.filter(
    (attachment) => attachment.variant === "original",
  );
}

function editablePrecision(value: FirstTimeDatePrecision | undefined) {
  if (value === "exact") {
    return "day";
  }

  if (value === "range") {
    return "approximate";
  }

  return value ?? "unknown";
}

function firstTimeDateLabel(entry: FirstTimeEntry) {
  if (entry.occurredLabel) {
    return entry.occurredLabel;
  }

  if (!entry.occurredStart) {
    return "Date not recorded";
  }

  const date = new Date(entry.occurredStart);
  const options: Intl.DateTimeFormatOptions =
    entry.datePrecision === "year"
      ? { year: "numeric" }
      : entry.datePrecision === "month"
        ? { month: "long", year: "numeric" }
        : { day: "numeric", month: "long", year: "numeric" };

  try {
    return new Intl.DateTimeFormat("en-US", {
      ...options,
      timeZone: entry.occurredTimezone ?? "UTC",
    }).format(date);
  } catch {
    return new Intl.DateTimeFormat("en-US", {
      ...options,
      timeZone: "UTC",
    }).format(date);
  }
}

function localTimezone() {
  return Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
}

function namesIncludingDraft(names: string[], draft: string) {
  const name = draft.trim();
  return name ? [...names, name] : names;
}

function countLabel(count: number, singular: string) {
  return `${count} ${count === 1 ? singular : `${singular}s`}`;
}

function truncate(value: string, limit: number) {
  return value.length > limit ? `${value.slice(0, limit).trimEnd()}…` : value;
}

function actionError(message: string): FirstTimeActionResult {
  return { entry: null, message, status: "error" };
}
