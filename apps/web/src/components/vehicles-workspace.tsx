"use client";
import { notify } from "@/components/app-toast";
import { FocusedEditorSurface } from "@/components/focused-editor-surface";
import { useConfirmationDialog } from "@/components/confirmation-dialog";
import { EmptyState } from "@/components/empty-state";
import { FocusedViewLayout } from "@/components/focused-view-layout";
import { Button } from "@/components/button";
import { Badge } from "@/components/badge";

import { useEffect, useRef, useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import {
  registerVehicleAttachment,
  saveVehicleEntry,
  trashVehicleAttachment,
  trashVehicleEntry,
  type VehicleActionResult,
} from "@/app/vehicles/actions";
import styles from "@/components/record-workspace.module.css";
import { EntryPhotoField } from "@/components/entry-photo-field";
import { EntryOrganizationEditor } from "@/components/entry-organization-editor";
import { LocationPicker } from "@/components/location-picker";
import { Icon } from "@/components/icon";
import { ProgressiveImage } from "@/components/progressive-image";
import { RecordCardMap } from "@/components/record-card-map";
import {
  RecordCard,
  RecordCardBody,
  RecordCardVisual,
} from "@/components/record-card";
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
import {
  uploadEntryPhotos,
  type PhotoUploadProgress as PhotoUploadProgressValue,
} from "@/lib/media/upload";
import type { CaptureExtractionSource } from "@/lib/data/capture-extraction-input";
import type { LocationSelection } from "@/lib/locations/location";

export function VehiclesWorkspace({
  collectionOptions,
  initialVehicleId,
  loadError,
  ownerId,
  sourceCapture,
  tagOptions,
  vehicles: serverRecords,
}: {
  collectionOptions: string[];
  initialVehicleId: string | null;
  loadError: string | null;
  ownerId: string;
  sourceCapture: CaptureExtractionSource | null;
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
  >(
    sourceCapture
      ? null
      : vehicles.find((vehicle) => vehicle.id === initialVehicleId),
  );
  const currentVehicles = vehicles.filter((vehicle) => !vehicle.occurredEnd);
  const earlierVehicles = vehicles.filter((vehicle) => vehicle.occurredEnd);
  const orderedVehicles = [...currentVehicles, ...earlierVehicles];

  return (
    <FocusedViewLayout
      actions={
        <Button
          variant="primary"
          aria-label="Add Vehicle"
          onClick={() => setSelectedVehicle(null)}
          type="button"
        >
          <Icon name="plus" />
          <span>Add Vehicle</span>
        </Button>
      }
      description={
        <>
          Keep each car, bike, or other vehicle as an Entity, with the dates,
          facts, and memories that made it yours.
        </>
      }
      eyebrow={<>The machines that carried your story</>}
      summary={
        <>
          <span>{countLabel(vehicles.length, "vehicle")}</span>
          <span aria-hidden="true">·</span>
          <span>{countLabel(currentVehicles.length, "current vehicle")}</span>
          <span aria-hidden="true">·</span>
          <span>{countLabel(earlierVehicles.length, "earlier vehicle")}</span>
        </>
      }
      summaryLabel="Vehicles summary"
      title={<>Vehicles</>}
    >
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
        <EmptyState
          title={<>Begin with a vehicle that carried you</>}
          icon={
            <>
              <Icon name="car" size={24} />
            </>
          }
          description={
            <>
              Add its name and best-known start date now. Specs, photos, and
              memories can come later.
            </>
          }
          onClick={() => setSelectedVehicle(null)}
        />
      ) : null}

      {!loadError && orderedVehicles.length > 0 ? (
        <VehicleSection
          label="Current first, followed by earlier vehicles"
          onSelect={(vehicle) => router.push(`/vehicles/${vehicle.id}`)}
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
            if (initialVehicleId || sourceCapture)
              router.replace("/vehicles", { scroll: false });
            else router.refresh();
          }}
          ownerId={ownerId}
          sourceCapture={selectedVehicle === null ? sourceCapture : null}
          tagOptions={tagOptions}
          vehicle={selectedVehicle}
        />
      ) : null}
    </FocusedViewLayout>
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
        {vehicles.map((vehicle, index) => (
          <VehicleCard
            eagerMap={index < 3}
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
  eagerMap,
  onSelect,
  vehicle,
}: {
  eagerMap: boolean;
  onSelect: () => void;
  vehicle: VehicleRecord;
}) {
  const cover = vehicle.attachments[0];

  return (
    <RecordCard
      ariaLabel={`${vehicle.title}, ${vehicleRangeLabel(vehicle)}`}
      className={styles.homeCard}
      onClick={onSelect}
    >
      <RecordCardVisual className={styles.homeVisual}>
        {cover?.imageUrl ? (
          <ProgressiveImage alt="" src={cover.imageUrl} />
        ) : (
          <RecordCardMap
            eager={eagerMap}
            fallback={
              <div className={styles.homeMark}>
                <Icon name="car" size={24} />
                <span>{vehicleFactsLabel(vehicle)}</span>
              </div>
            }
            latitude={vehicle.location?.latitude}
            longitude={vehicle.location?.longitude}
          />
        )}
        <Badge
          className={
            vehicle.occurredEnd ? styles.pastBadge : styles.currentBadge
          }
          size="micro"
          tone={vehicle.occurredEnd ? "glassNeutral" : "glassAccent"}
          uppercase
        >
          {vehicle.occurredEnd ? "Earlier" : "Current"}
        </Badge>
        {vehicle.attachments.length > 1 ? (
          <Badge
            className={styles.photoBadge}
            size="micro"
            tone="inverse"
            uppercase
          >
            {vehicle.attachments.length} photos
          </Badge>
        ) : null}
      </RecordCardVisual>

      <RecordCardBody className={styles.cardBody}>
        <div className={styles.cardDates}>
          <time>{vehicleRangeLabel(vehicle)}</time>
          <span>{vehicleDurationLabel(vehicle)}</span>
        </div>
        <h3>{vehicle.title}</h3>
        <p className={styles.location}>
          <Icon name="car" size={14} />
          {vehicleFactsLabel(vehicle)}
        </p>
        {vehicle.location ? (
          <p className={styles.location}>
            <Icon name="map" size={14} />
            {vehicle.location.name}
          </p>
        ) : null}
        {vehicle.body ? (
          <p className={styles.memory}>{truncate(vehicle.body, 150)}</p>
        ) : null}
        <footer>
          <div>
            {vehicle.collectionNames.slice(0, 2).map((name) => (
              <Badge
                key={`collection:${name.toLocaleLowerCase()}`}
                size="micro"
                tone="neutral"
              >
                {name}
              </Badge>
            ))}
            {vehicle.tagNames.slice(0, 2).map((name) => (
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

export function VehicleEditor({
  collectionOptions,
  defaultTimezone,
  onClose,
  onSaved,
  onTrashed,
  ownerId,
  presentation = "dialog",
  sourceCapture = null,
  tagOptions,
  vehicle,
}: {
  collectionOptions: string[];
  defaultTimezone?: string;
  onClose: () => void;
  onSaved: (record: VehicleRecord) => void;
  onTrashed: (id: string) => void;
  ownerId: string;
  presentation?: "dialog" | "page";
  sourceCapture?: CaptureExtractionSource | null;
  tagOptions: string[];
  vehicle: VehicleRecord | null;
}) {
  const router = useRouter();
  const requestConfirmation = useConfirmationDialog();
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
    : (sourceCapture ?? undefined);
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
  const [body, setBody] = useState(vehicle?.body ?? sourceCapture?.body ?? "");
  const [collectionInput, setCollectionInput] = useState("");
  const [collectionNames, setCollectionNames] = useState(
    vehicle?.collectionNames ?? sourceCapture?.collectionNames ?? [],
  );
  const [color, setColor] = useState(vehicle?.color ?? "");
  const [currentId, setCurrentId] = useState(vehicle?.id ?? null);
  const [currentRevision, setCurrentRevision] = useState(
    vehicle?.revision ?? null,
  );
  const [location, setLocation] = useState<LocationSelection | null>(
    vehicle?.location ?? null,
  );
  const [locationDirty, setLocationDirty] = useState(false);
  const [existingPhotos, setExistingPhotos] = useState(
    vehicle?.attachments ?? [],
  );
  const [isPending, setIsPending] = useState(false);
  const [photoUploadProgress, setPhotoUploadProgress] =
    useState<PhotoUploadProgressValue | null>(null);
  const [make, setMake] = useState(vehicle?.make ?? "");
  const [model, setModel] = useState(vehicle?.model ?? "");
  const [modelYear, setModelYear] = useState(
    vehicle?.modelYear?.toString() ?? "",
  );
  const [pendingPhotos, setPendingPhotos] = useState<File[]>([]);
  const [result, setResult] = useState<VehicleActionResult | null>(null);
  const [tagInput, setTagInput] = useState("");
  const [tagNames, setTagNames] = useState(
    vehicle?.tagNames ?? sourceCapture?.tagNames ?? [],
  );
  const [title, setTitle] = useState(
    vehicle?.title ?? sourceCapture?.title ?? "",
  );

  useEffect(() => {
    titleRef.current?.focus();
  }, []);

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
      const saved = await saveVehicleEntry(
        parsed.data,
        sourceCapture
          ? { id: sourceCapture.id, revision: sourceCapture.revision }
          : null,
        locationDirty ? location : undefined,
      );
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
        location,
        timelineTrackId: vehicle?.timelineTrackId ?? null,
        timelineTrackName: vehicle?.timelineTrackName ?? "Vehicles",
        totalCount: vehicle?.totalCount ?? 1,
        updatedAt: new Date().toISOString(),
      });
      setCurrentId(saved.entry.id);
      setCurrentRevision(saved.entry.revision);
      setLocationDirty(false);
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
            `The Vehicle was saved, but ${countLabel(failedPhotos.length, "photo")} could not be attached. Select Save again to retry.`,
          ),
        );
        router.refresh();
        return;
      }

      notify.success(
        saved.status === "created" ? "Vehicle created." : "Vehicle saved.",
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

  async function handleRemovePhoto(photo: VehicleAttachment) {
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
      const nextResult = await trashVehicleAttachment({
        attachmentId: photo.id,
      });
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
      title: <>Move “{title.trim() || "this Vehicle"}” to Trash?</>,
      description: <>Its history and private photos will be preserved.</>,
      confirmLabel: "Move to Trash",
      eyebrow: <>Recoverable action</>,
      variant: "danger",
    });
    if (!confirmed) return;
    setIsPending(true);
    setResult(null);
    try {
      const nextResult = await trashVehicleEntry({
        id: currentId,
        revision: currentRevision,
      });
      if (nextResult.status === "trashed") {
        onTrashed(currentId);
        onClose();
        notify.info("Vehicle moved to Trash.");
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
    <FocusedEditorSurface
      onClose={onClose}
      presentation={presentation}
      title={
        <>
          {currentId
            ? title || "Vehicle"
            : sourceCapture
              ? "Create a Vehicle from this Capture"
              : "Keep a Vehicle in your Life Wiki"}
        </>
      }
      titleId="vehicle-editor-title"
      eyebrow={<>{currentId ? "Edit Vehicle" : "New Vehicle"}</>}
      closeLabel="Close Vehicle editor"
      busy={isPending}
      footer={
        <div className={styles.dialogFooter}>
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
              form="vehicles-workspace-form"
              variant="primary"
              disabled={isPending}
              type="submit"
            >
              {isPending
                ? "Saving..."
                : currentId
                  ? "Save changes"
                  : "Add Vehicle"}
            </Button>
          </div>
        </div>
      }
    >
      {" "}
      <form id="vehicles-workspace-form" onSubmit={handleSubmit}>
        <div className={styles.formGrid}>
          {sourceCapture ? (
            <div className={styles.extractionNotice}>
              <Icon name="inbox" size={18} />
              <div>
                <strong>Starting from an Inbox Capture</strong>
                <p>
                  Saving creates a separate Vehicle and links it to the
                  preserved source Capture.
                </p>
              </div>
            </div>
          ) : null}
          <fieldset className={styles.formSection}>
            <legend>Vehicle details</legend>
            <label className={styles.fullField}>
              <span>
                Name or nickname <span aria-hidden="true">*</span>
              </span>
              <input
                aria-label="Name or nickname"
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
            <div className={styles.fullField}>
              <LocationPicker
                disabled={isPending}
                onChange={(selection) => {
                  setLocation(selection);
                  setLocationDirty(true);
                }}
                value={location}
              />
            </div>
          </fieldset>

          <fieldset className={styles.formSection}>
            <legend>Vehicle facts</legend>
            <label>
              <span>Make</span>
              <input
                maxLength={vehicleMakeLimit}
                onChange={(event) => setMake(event.target.value)}
                placeholder="Honda"
                value={make}
              />
            </label>
            <label>
              <span>Model</span>
              <input
                maxLength={vehicleModelLimit}
                onChange={(event) => setModel(event.target.value)}
                placeholder="Civic"
                value={model}
              />
            </label>
            <label>
              <span>Model year</span>
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
              <span>Color</span>
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
              <span>Memories</span>
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
            recordLabel="Vehicle"
          />
        </div>

        {result ? (
          <p className={styles.formMessage} role="alert">
            {result.message}
          </p>
        ) : null}
      </form>
    </FocusedEditorSurface>
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
    registerVehicleAttachment,
    onProgress,
  );
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
