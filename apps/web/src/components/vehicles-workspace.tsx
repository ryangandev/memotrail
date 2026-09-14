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
  registerVehicleAttachment,
  saveVehicleEntry,
  trashVehicleAttachment,
  trashVehicleEntry,
  type VehicleActionResult,
} from "@/app/vehicles/actions";
import styles from "@/app/homes/page.module.css";
import { EntryOrganizationEditor } from "@/components/entry-organization-editor";
import { Icon } from "@/components/icon";
import { PageFrame } from "@/components/page-frame";
import { ProgressiveImage } from "@/components/progressive-image";
import {
  firstTimePhotoLimit,
  firstTimePhotoSizeLimit,
  inferFirstTimeImageMimeType,
} from "@/lib/data/first-time-input";
import { OccurrenceEditor } from "@/components/occurrence-editor";
import {
  occurrenceDraft,
  resolveOccurrenceDraft,
  type Occurrence,
} from "@/lib/data/occurrence";
import {
  vehicleDurationLabel,
  vehicleFactsLabel,
  vehicleRangeLabel,
  type VehicleAttachment,
  type VehicleRecord,
} from "@/lib/data/vehicle-record";
import {
  parseVehicleEntryInput,
  vehicleBodyLimit,
  vehicleColorLimit,
  vehicleMakeLimit,
  vehicleModelLimit,
  vehicleTitleLimit,
  type VehicleEntryInput,
} from "@/lib/data/vehicle-record-input";
import { useConfirmedRecords } from "@/components/use-confirmed-records";
import { uploadEntryPhotos } from "@/lib/media/upload";

export function VehiclesWorkspace({
  collectionOptions,
  initialVehicleId,
  loadError,
  ownerId,
  tagOptions,
  vehicles: serverRecords,
}: {
  collectionOptions: string[];
  initialVehicleId: string | null;
  loadError: string | null;
  ownerId: string;
  tagOptions: string[];
  vehicles: VehicleRecord[];
}) {
  const router = useRouter();
  const {
    records: vehicles,
    confirm,
    forget,
  } = useConfirmedRecords(serverRecords);
  const [selectedVehicle, setSelectedVehicle] = useState<
    VehicleRecord | null | undefined
  >(vehicles.find((vehicle) => vehicle.id === initialVehicleId));
  const currentVehicles = vehicles.filter((vehicle) => !vehicle.occurredEnd);
  const earlierVehicles = vehicles.filter((vehicle) => vehicle.occurredEnd);
  const orderedVehicles = [...currentVehicles, ...earlierVehicles];

  return (
    <PageFrame variant="wide">
      <header className={styles.pageHeader}>
        <div>
          <p className={styles.eyebrow}>The machines that carried your story</p>
          <h1>Vehicles</h1>
          <p>
            Keep each car, bike, or other vehicle as a chapter, with the dates,
            details, and memories that made it yours.
          </p>
        </div>
        <button
          aria-label="Add Vehicle"
          className={styles.addButton}
          onClick={() => setSelectedVehicle(null)}
          type="button"
        >
          <Icon name="plus" />
          <span>Add Vehicle</span>
        </button>
      </header>

      <div className={styles.summary} aria-label="Vehicles summary">
        <span>{countLabel(vehicles.length, "vehicle")}</span>
        <span aria-hidden="true">·</span>
        <span>{countLabel(currentVehicles.length, "current vehicle")}</span>
        <span aria-hidden="true">·</span>
        <span>{countLabel(earlierVehicles.length, "earlier vehicle")}</span>
      </div>

      {loadError ? (
        <div className={styles.message} role="alert">
          <Icon name="car" size={22} />
          <div>
            <strong>Vehicles unavailable</strong>
            <p>{loadError}</p>
          </div>
        </div>
      ) : null}

      {!loadError && vehicles.length === 0 ? (
        <button
          className={styles.emptyState}
          onClick={() => setSelectedVehicle(null)}
          type="button"
        >
          <span className={styles.emptyMark}>
            <Icon name="car" size={24} />
          </span>
          <strong>Begin with a vehicle that carried you</strong>
          <span>
            Add its name and best-known start date now. Specs, photos, and
            memories can come later.
          </span>
        </button>
      ) : null}

      {!loadError && orderedVehicles.length > 0 ? (
        <VehicleSection
          label="Current first, followed by earlier chapters"
          onSelect={setSelectedVehicle}
          title="Vehicle archive"
          vehicles={orderedVehicles}
        />
      ) : null}

      {selectedVehicle !== undefined ? (
        <VehicleEditor
          collectionOptions={collectionOptions}
          key={selectedVehicle?.id ?? "new-vehicle"}
          onSaved={confirm}
          onTrashed={forget}
          onClose={() => {
            setSelectedVehicle(undefined);
            if (initialVehicleId)
              router.replace("/vehicles", { scroll: false });
          }}
          ownerId={ownerId}
          tagOptions={tagOptions}
          vehicle={selectedVehicle}
        />
      ) : null}
    </PageFrame>
  );
}

function VehicleSection({
  label,
  onSelect,
  title,
  vehicles,
}: {
  label: string;
  onSelect: (vehicle: VehicleRecord) => void;
  title: string;
  vehicles: VehicleRecord[];
}) {
  return (
    <section className={styles.homeSection}>
      <header>
        <h2>{title}</h2>
        <span>{label}</span>
      </header>
      <div className={styles.homeGrid}>
        {vehicles.map((vehicle) => (
          <VehicleCard
            key={vehicle.id}
            onSelect={() => onSelect(vehicle)}
            vehicle={vehicle}
          />
        ))}
      </div>
    </section>
  );
}

function VehicleCard({
  onSelect,
  vehicle,
}: {
  onSelect: () => void;
  vehicle: VehicleRecord;
}) {
  const cover = vehicle.attachments[0];

  return (
    <button
      aria-label={`${vehicle.title}, ${vehicleRangeLabel(vehicle)}`}
      className={styles.homeCard}
      onClick={onSelect}
      type="button"
    >
      <div className={styles.homeVisual}>
        {cover?.imageUrl ? (
          <ProgressiveImage alt="" src={cover.imageUrl} />
        ) : (
          <div className={styles.homeMark}>
            <Icon name="car" size={24} />
            <span>{vehicleFactsLabel(vehicle)}</span>
          </div>
        )}
        <span
          className={
            vehicle.occurredEnd ? styles.pastBadge : styles.currentBadge
          }
        >
          {vehicle.occurredEnd ? "Earlier" : "Current"}
        </span>
        {vehicle.attachments.length > 1 ? (
          <small>{vehicle.attachments.length} photos</small>
        ) : null}
      </div>

      <div className={styles.cardBody}>
        <div className={styles.cardDates}>
          <time>{vehicleRangeLabel(vehicle)}</time>
          <span>{vehicleDurationLabel(vehicle)}</span>
        </div>
        <h3>{vehicle.title}</h3>
        <p className={styles.location}>
          <Icon name="car" size={14} />
          {vehicleFactsLabel(vehicle)}
        </p>
        {vehicle.body ? (
          <p className={styles.memory}>{truncate(vehicle.body, 150)}</p>
        ) : null}
        <footer>
          <div>
            {vehicle.collectionNames.slice(0, 2).map((name) => (
              <span key={`collection:${name.toLocaleLowerCase()}`}>{name}</span>
            ))}
            {vehicle.tagNames.slice(0, 2).map((name) => (
              <span key={`tag:${name.toLocaleLowerCase()}`}>#{name}</span>
            ))}
          </div>
          <Icon name="chevron" size={15} />
        </footer>
      </div>
    </button>
  );
}

export function VehicleEditor({
  collectionOptions,
  defaultTimezone,
  onClose,
  onSaved,
  onTrashed,
  ownerId,
  tagOptions,
  vehicle,
}: {
  collectionOptions: string[];
  defaultTimezone?: string;
  onClose: () => void;
  onSaved: (record: VehicleRecord) => void;
  onTrashed: (id: string) => void;
  ownerId: string;
  tagOptions: string[];
  vehicle: VehicleRecord | null;
}) {
  const router = useRouter();
  const titleRef = useRef<HTMLInputElement>(null);
  const initialTimezone =
    vehicle?.occurredTimezone ?? defaultTimezone ?? localTimezone();
  const originalOccurrence: Occurrence | undefined = vehicle
    ? {
        occurredAt: vehicle.occurredStart,
        occurredEnd: vehicle.occurredEnd,
        occurredLabel: vehicle.occurredLabel,
        occurredTimezone: initialTimezone,
        datePrecision: vehicle.datePrecision,
      }
    : undefined;
  const [occurrence, setOccurrence] = useState(() =>
    occurrenceDraft(
      originalOccurrence ?? {
        occurredAt: null,
        occurredEnd: null,
        occurredLabel: null,
        occurredTimezone: initialTimezone,
        datePrecision: "unknown",
      },
    ),
  );
  const [body, setBody] = useState(vehicle?.body ?? "");
  const [collectionInput, setCollectionInput] = useState("");
  const [collectionNames, setCollectionNames] = useState(
    vehicle?.collectionNames ?? [],
  );
  const [color, setColor] = useState(vehicle?.color ?? "");
  const [currentId, setCurrentId] = useState(vehicle?.id ?? null);
  const [currentRevision, setCurrentRevision] = useState(
    vehicle?.revision ?? null,
  );
  const [existingPhotos, setExistingPhotos] = useState(
    vehicle?.attachments ?? [],
  );
  const [isPending, setIsPending] = useState(false);
  const [make, setMake] = useState(vehicle?.make ?? "");
  const [model, setModel] = useState(vehicle?.model ?? "");
  const [modelYear, setModelYear] = useState(
    vehicle?.modelYear?.toString() ?? "",
  );
  const [pendingPhotos, setPendingPhotos] = useState<File[]>([]);
  const [result, setResult] = useState<VehicleActionResult | null>(null);
  const [tagInput, setTagInput] = useState("");
  const [tagNames, setTagNames] = useState(vehicle?.tagNames ?? []);
  const [title, setTitle] = useState(vehicle?.title ?? "");

  useEffect(() => {
    titleRef.current?.focus();
  }, []);

  useEffect(() => {
    titleRef.current?.focus();
    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape" && !isPending) onClose();
    }
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [isPending, onClose]);

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
      errorMessage = `Keep up to ${firstTimePhotoLimit} photos on a Vehicle.`;
    }

    setPendingPhotos((current) => [...current, ...accepted]);
    setResult(errorMessage ? actionError(errorMessage) : null);
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const resolved = resolveOccurrenceDraft(
      occurrence,
      originalOccurrence,
      true,
    );
    if (!resolved.value) {
      setResult(actionError(resolved.error));
      return;
    }
    const input: VehicleEntryInput = {
      body,
      collectionNames: namesIncludingDraft(collectionNames, collectionInput),
      color: color || null,
      datePrecision: resolved.value.datePrecision,
      id: currentId,
      make: make || null,
      model: model || null,
      modelYear: modelYear.trim() ? Number(modelYear) : null,
      occurredEnd: resolved.value.occurredEnd,
      occurredLabel: resolved.value.occurredLabel,
      occurredStart: resolved.value.occurredAt,
      occurredTimezone: resolved.value.occurredTimezone,
      revision: currentRevision,
      tagNames: namesIncludingDraft(tagNames, tagInput),
      title,
    };
    const parsed = parseVehicleEntryInput(input);
    if (!parsed.success) {
      setResult(actionError(parsed.message));
      return;
    }

    setIsPending(true);
    setResult(null);
    try {
      const saved = await saveVehicleEntry(parsed.data);
      if (
        (saved.status !== "created" && saved.status !== "saved") ||
        !saved.entry
      ) {
        setResult(saved);
        return;
      }

      onSaved({
        ...parsed.data,
        ...saved.entry,
        attachments: existingPhotos,
        timelineTrackId: vehicle?.timelineTrackId ?? null,
        timelineTrackName: vehicle?.timelineTrackName ?? "Vehicles",
        totalCount: vehicle?.totalCount ?? 1,
        updatedAt: new Date().toISOString(),
      });
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
            `The Vehicle was saved, but ${countLabel(failedPhotos.length, "photo")} could not be attached. Select Save again to retry.`,
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

  async function handleRemovePhoto(photo: VehicleAttachment) {
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
      const nextResult = await trashVehicleAttachment({
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
        `Move “${title.trim() || "this Vehicle"}” to Trash? Its history and private photos will be preserved.`,
      )
    ) {
      return;
    }
    setIsPending(true);
    setResult(null);
    try {
      const nextResult = await trashVehicleEntry({
        id: currentId,
        revision: currentRevision,
      });
      if (nextResult.status === "trashed") {
        onTrashed(currentId);
        router.refresh();
        onClose();
      } else {
        setResult(nextResult);
      }
    } catch {
      setResult(actionError("MemoTrail could not move this Vehicle to Trash."));
    } finally {
      setIsPending(false);
    }
  }

  return (
    <div
      aria-labelledby="vehicle-editor-title"
      aria-modal="true"
      className={styles.dialogBackdrop}
      onMouseDown={(event) => {
        if (event.currentTarget === event.target && !isPending) onClose();
      }}
      role="dialog"
    >
      <div className={styles.dialogPanel}>
        <header className={styles.dialogHeader}>
          <div>
            <p>{currentId ? "Edit Vehicle" : "New Vehicle"}</p>
            <h2 id="vehicle-editor-title">
              {currentId ? title || "Vehicle" : "Keep a ride in your story"}
            </h2>
          </div>
          <button
            aria-label="Close Vehicle editor"
            disabled={isPending}
            onClick={onClose}
            type="button"
          >
            ×
          </button>
        </header>

        <form onSubmit={handleSubmit}>
          <div className={styles.formGrid}>
            <fieldset className={styles.formSection}>
              <legend>Vehicle chapter</legend>
              <label className={styles.fullField}>
                <span>Name or nickname</span>
                <input
                  maxLength={vehicleTitleLimit}
                  onChange={(event) => setTitle(event.target.value)}
                  placeholder="Blue Civic"
                  ref={titleRef}
                  required
                  value={title}
                />
              </label>
              <div className={styles.fullField}>
                <OccurrenceEditor
                  value={occurrence}
                  onChange={setOccurrence}
                  disabled={isPending}
                  span
                />
              </div>
            </fieldset>

            <fieldset className={styles.formSection}>
              <legend>Vehicle facts</legend>
              <label>
                <span>
                  Make <small>Optional</small>
                </span>
                <input
                  maxLength={vehicleMakeLimit}
                  onChange={(event) => setMake(event.target.value)}
                  placeholder="Honda"
                  value={make}
                />
              </label>
              <label>
                <span>
                  Model <small>Optional</small>
                </span>
                <input
                  maxLength={vehicleModelLimit}
                  onChange={(event) => setModel(event.target.value)}
                  placeholder="Civic"
                  value={model}
                />
              </label>
              <label>
                <span>
                  Model year <small>Optional</small>
                </span>
                <input
                  inputMode="numeric"
                  max={2200}
                  min={1886}
                  onChange={(event) => setModelYear(event.target.value)}
                  placeholder="2018"
                  type="number"
                  value={modelYear}
                />
              </label>
              <label>
                <span>
                  Color <small>Optional</small>
                </span>
                <input
                  maxLength={vehicleColorLimit}
                  onChange={(event) => setColor(event.target.value)}
                  placeholder="Midnight blue"
                  value={color}
                />
              </label>
            </fieldset>

            <fieldset className={styles.formSection}>
              <legend>Memories and organization</legend>
              <label className={styles.fullField}>
                <span>
                  Memories <small>Optional</small>
                </span>
                <textarea
                  maxLength={vehicleBodyLimit}
                  onChange={(event) => setBody(event.target.value)}
                  placeholder="Where did it take you? What do you want to remember?"
                  rows={5}
                  value={body}
                />
              </label>
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

            <fieldset className={`${styles.photoField} ${styles.formSection}`}>
              <legend>Photos</legend>
              {existingPhotos.length > 0 || pendingPhotos.length > 0 ? (
                <div className={styles.photoGrid}>
                  {existingPhotos.map((photo) => (
                    <div className={styles.photoTile} key={photo.id}>
                      {photo.imageUrl ? (
                        <ProgressiveImage
                          alt={photo.originalFilename ?? "Vehicle photo"}
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
                    : "Add Vehicle"}
              </button>
            </div>
          </footer>
        </form>
      </div>
    </div>
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
    <div className={`${styles.photoTile} ${styles.pendingPhoto}`}>
      <ProgressiveImage alt={`Selected ${file.name}`} src={previewUrl} />
      <span className={styles.pendingBadge}>New</span>
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
  return uploadEntryPhotos(ownerId, entryId, photos, registerVehicleAttachment);
}

function namesIncludingDraft(names: string[], draft: string) {
  const name = draft.trim();
  return name ? [...names, name] : names;
}

function localTimezone() {
  return Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
}

function actionError(message: string): VehicleActionResult {
  return { entry: null, message, status: "error" };
}

function countLabel(count: number, singular: string) {
  return `${count} ${count === 1 ? singular : `${singular}s`}`;
}

function truncate(value: string, limit: number) {
  return value.length > limit ? `${value.slice(0, limit).trimEnd()}...` : value;
}
