"use client";
import { notify } from "@/components/app-toast";
import { FocusedEditorSurface } from "@/components/focused-editor-surface";
import { useConfirmationDialog } from "@/components/confirmation-dialog";
import { EmptyState } from "@/components/empty-state";
import { FocusedViewLayout } from "@/components/focused-view-layout";
import { SeparatedList } from "@/components/separated-list";
import { Button } from "@/components/button";
import { Badge } from "@/components/badge";

import { useEffect, useRef, useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import {
  registerHomeAttachment,
  saveHomeEntry,
  trashHomeAttachment,
  trashHomeEntry,
  type HomeActionResult,
} from "@/app/homes/actions";
import styles from "@/components/record-workspace.module.css";
import { EntryPhotoField } from "@/components/entry-photo-field";
import { EntryOrganizationEditor } from "@/components/entry-organization-editor";
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
import {
  homeBodyLimit,
  homeTitleLimit,
  parseHomeEntryInput,
  type HomeEntryInput,
} from "@/lib/data/home-record-input";
import {
  homeDurationLabel,
  homeLocationLabel,
  homeRangeLabel,
  type HomeAttachment,
  type HomeRecord,
} from "@/lib/data/home-record";
import { OccurrenceEditor } from "@/components/occurrence-editor";
import { LocationPicker } from "@/components/location-picker";
import {
  savedLocationSelection,
  type ExistingLocation,
  type LocationInput,
  type LocationSelection,
} from "@/lib/locations/location";
import {
  occurrenceDraft,
  resolveOccurrenceDraft,
  type Occurrence,
} from "@/lib/data/occurrence";
import { useConfirmedRecords } from "@/components/use-confirmed-records";
import {
  uploadEntryPhotos,
  type PhotoUploadProgress as PhotoUploadProgressValue,
} from "@/lib/media/upload";
import { countLabel } from "@/lib/count-label";

export function HomesWorkspace({
  homes: serverRecords,
  loadError,
  ownerId,
  tagOptions,
}: {
  homes: HomeRecord[];
  loadError: string | null;
  ownerId: string;
  tagOptions: string[];
}) {
  const router = useRouter();
  const {
    records: homes,
    confirm,
    forget,
  } = useConfirmedRecords(serverRecords);
  const [selectedHome, setSelectedHome] = useState<
    HomeRecord | null | undefined
  >();
  const currentHomes = homes.filter((home) => !home.occurredEnd);
  const earlierHomes = homes.filter((home) => home.occurredEnd);

  return (
    <FocusedViewLayout
      actions={
        <Button
          variant="primary"
          aria-label="Add Home"
          onClick={() => setSelectedHome(null)}
          type="button"
        >
          <Icon name="plus" />
          <span>Add Home</span>
        </Button>
      }
      description={
        <>
          Keep each residence as a Home Entity, with the dates, location, and
          memories that made it yours.
        </>
      }
      eyebrow={<>The places that held your life</>}
      summary={
        <SeparatedList>
          <span>{countLabel(homes.length, "home")}</span>
          <span>{countLabel(currentHomes.length, "current residence")}</span>
          <span>{countLabel(earlierHomes.length, "earlier home")}</span>
        </SeparatedList>
      }
      summaryLabel="Homes summary"
      title={<>Homes</>}
    >
      {loadError ? (
        <div className={styles.message} role="alert">
          <Icon name="home" size={22} />
          <div>
            <strong>Homes unavailable</strong>
            <p>{loadError}</p>
          </div>
        </div>
      ) : null}

      {!loadError && homes.length === 0 ? (
        <EmptyState
          title={<>Begin with somewhere you called home</>}
          icon={
            <>
              <Icon name="home" size={24} />
            </>
          }
          description={
            <>
              Add the best-known move-in date now. Exact addresses, reasons,
              photos, and memories can come later.
            </>
          }
          onClick={() => setSelectedHome(null)}
        />
      ) : null}

      {!loadError && currentHomes.length > 0 ? (
        <HomeSection
          homes={currentHomes}
          label="Where life is happening now"
          onSelect={(home) => router.push(`/homes/${home.id}`)}
          title="Current"
        />
      ) : null}

      {!loadError && earlierHomes.length > 0 ? (
        <HomeSection
          homes={earlierHomes}
          label="Places you lived before"
          onSelect={(home) => router.push(`/homes/${home.id}`)}
          title="Earlier homes"
        />
      ) : null}

      {selectedHome !== undefined ? (
        <HomeEditor
          home={selectedHome}
          key={selectedHome?.id ?? "new-home"}
          onSaved={confirm}
          onTrashed={forget}
          onClose={() => setSelectedHome(undefined)}
          ownerId={ownerId}
          tagOptions={tagOptions}
        />
      ) : null}
    </FocusedViewLayout>
  );
}

function HomeSection({
  homes,
  label,
  onSelect,
  title,
}: {
  homes: HomeRecord[];
  label: string;
  onSelect: (home: HomeRecord) => void;
  title: string;
}) {
  return (
    <section className={styles.homeSection}>
      <header>
        <h2>{title}</h2>
        <span>{label}</span>
      </header>
      <div className={styles.homeGrid}>
        {homes.map((home, index) => (
          <HomeCard
            eagerMap={index < 3}
            home={home}
            key={home.id}
            onSelect={() => onSelect(home)}
          />
        ))}
      </div>
    </section>
  );
}

function HomeCard({
  eagerMap,
  home,
  onSelect,
}: {
  eagerMap: boolean;
  home: HomeRecord;
  onSelect: () => void;
}) {
  const cover = home.attachments[0];

  return (
    <RecordCard
      ariaLabel={`${home.title}, ${homeRangeLabel(home)}`}
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
                <Icon name="home" size={24} />
                <span>
                  {home.location?.city ??
                    home.location?.country ??
                    "A place in your trail"}
                </span>
              </div>
            }
            latitude={home.location?.latitude}
            longitude={home.location?.longitude}
          />
        )}
        <Badge
          className={home.occurredEnd ? styles.pastBadge : styles.currentBadge}
          size="micro"
          tone={home.occurredEnd ? "glassNeutral" : "glassAccent"}
          uppercase
        >
          {home.occurredEnd ? "Earlier" : "Current"}
        </Badge>
        {home.attachments.length > 1 ? (
          <Badge
            className={styles.photoBadge}
            size="micro"
            tone="inverse"
            uppercase
          >
            {home.attachments.length} photos
          </Badge>
        ) : null}
      </RecordCardVisual>

      <RecordCardBody className={styles.cardBody}>
        <div className={styles.cardDates}>
          <time>{homeRangeLabel(home)}</time>
          <span>{homeDurationLabel(home)}</span>
        </div>
        <h3>{home.title}</h3>
        <p className={styles.location}>
          <Icon name="map" size={14} />
          {homeLocationLabel(home)}
        </p>
        {home.body ? (
          <p className={styles.memory}>{truncate(home.body, 150)}</p>
        ) : null}
        <footer>
          <div>
            {home.tagNames.slice(0, 2).map((name) => (
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

export function HomeEditor({
  defaultTimezone,
  home,
  onClose,
  onSaved,
  onTrashed,
  ownerId,
  presentation = "dialog",
  tagOptions,
}: {
  defaultTimezone?: string;
  home: HomeRecord | null;
  onClose: () => void;
  onSaved: (record: HomeRecord) => void;
  onTrashed: (id: string) => void;
  ownerId: string;
  presentation?: "dialog" | "page";
  tagOptions: string[];
}) {
  const router = useRouter();
  const requestConfirmation = useConfirmationDialog();
  const titleRef = useRef<HTMLInputElement>(null);
  const initialTimezone =
    home?.occurredTimezone ?? defaultTimezone ?? localTimezone();
  const originalOccurrence: Occurrence | undefined = home
    ? {
        occurredAt: home.occurredStart,
        occurredEnd: home.occurredEnd,
        occurredLabel: home.occurredLabel,
        occurredTimezone: initialTimezone,
        datePrecision: home.datePrecision,
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
  const [address, setAddress] = useState(home?.location?.address ?? "");
  const [body, setBody] = useState(home?.body ?? "");
  const [city, setCity] = useState(home?.location?.city ?? "");
  const [country, setCountry] = useState(home?.location?.country ?? "");
  const [currentId, setCurrentId] = useState(home?.id ?? null);
  const [currentRevision, setCurrentRevision] = useState(
    home?.revision ?? null,
  );
  const [existingPhotos, setExistingPhotos] = useState(home?.attachments ?? []);
  const [isPending, setIsPending] = useState(false);
  const [photoUploadProgress, setPhotoUploadProgress] =
    useState<PhotoUploadProgressValue | null>(null);
  const [moveInReason, setMoveInReason] = useState(home?.moveInReason ?? "");
  const [moveOutReason, setMoveOutReason] = useState(home?.moveOutReason ?? "");
  const [pendingPhotos, setPendingPhotos] = useState<File[]>([]);
  const [location, setLocation] = useState<LocationSelection | null>(
    home?.location ?? null,
  );
  const [locationDirty, setLocationDirty] = useState(false);
  const [region, setRegion] = useState(home?.location?.region ?? "");
  const [result, setResult] = useState<HomeActionResult | null>(null);
  const [tagInput, setTagInput] = useState("");
  const [tagNames, setTagNames] = useState(home?.tagNames ?? []);
  const [title, setTitle] = useState(home?.title ?? "");

  useEffect(() => {
    titleRef.current?.focus();
  }, []);

  function chooseLocation(selection: LocationSelection | null) {
    setLocation(selection);
    setLocationDirty(true);
    setAddress(selection?.address ?? "");
    setCity(selection?.city ?? "");
    setRegion(selection?.region ?? "");
    setCountry(selection?.country ?? "");
  }

  /** Typing an address part replaces any chosen search result. */
  function typeAddressPart(setPart: (value: string) => void, value: string) {
    setLocation(null);
    setLocationDirty(true);
    setPart(value);
  }

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
      errorMessage = `Keep up to ${firstTimePhotoLimit} photos on a Home.`;
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
    const input: HomeEntryInput = {
      body,
      datePrecision: resolved.value.datePrecision,
      id: currentId,
      moveInReason: moveInReason || null,
      moveOutReason: moveOutReason || null,
      occurredEnd: resolved.value.occurredEnd,
      occurredLabel: resolved.value.occurredLabel,
      occurredStart: resolved.value.occurredAt,
      occurredTimezone: resolved.value.occurredTimezone,
      revision: currentRevision,
      tagNames: namesIncludingDraft(tagNames, tagInput),
      title,
    };
    const parsed = parseHomeEntryInput(input);

    if (!parsed.success) {
      setResult(actionError(parsed.message));
      return;
    }

    setIsPending(true);
    setResult(null);

    try {
      const locationInput = locationDirty
        ? (location ?? manualLocation(address, city, region, country))
        : undefined;
      const saved = await saveHomeEntry(parsed.data, locationInput);
      if (
        (saved.status !== "created" && saved.status !== "saved") ||
        !saved.entry
      ) {
        setResult(saved);
        return;
      }

      const savedLocation =
        locationInput === undefined
          ? (home?.location ?? null)
          : savedHomeLocation(locationInput, saved.entry.locationId ?? null);
      onSaved({
        ...parsed.data,
        id: saved.entry.id,
        revision: saved.entry.revision,
        attachments: existingPhotos,
        location: savedLocation,
        timelineTrackId: home?.timelineTrackId ?? null,
        timelineTrackName: home?.timelineTrackName ?? "Homes",
        totalCount: home?.totalCount ?? 1,
        updatedAt: new Date().toISOString(),
      });
      setCurrentId(saved.entry.id);
      setCurrentRevision(saved.entry.revision);
      setLocation(savedLocation);
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
            `The Home was saved, but ${countLabel(failedPhotos.length, "photo")} could not be attached. Select Save again to retry.`,
          ),
        );
        router.refresh();
        return;
      }

      router.refresh();
      notify.success(
        saved.status === "created" ? "Home created." : "Home saved.",
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

  async function handleRemovePhoto(photo: HomeAttachment) {
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
      const nextResult = await trashHomeAttachment({ attachmentId: photo.id });
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
      title: <>Move “{title.trim() || "this Home"}” to Trash?</>,
      description: (
        <>
          It, its Location, and its private photos can be restored from Trash.
        </>
      ),
      confirmLabel: "Move to Trash",
      eyebrow: <>Recoverable action</>,
      variant: "danger",
    });
    if (!confirmed) return;

    setIsPending(true);
    setResult(null);
    try {
      const nextResult = await trashHomeEntry({
        id: currentId,
        revision: currentRevision,
      });
      if (nextResult.status === "trashed") {
        onTrashed(currentId);
        onClose();
        notify.info("Home moved to Trash.");
      } else {
        setResult(nextResult);
      }
    } catch {
      setResult(actionError("MemoTrail could not move this Home to Trash."));
    } finally {
      setIsPending(false);
    }
  }

  return (
    <FocusedEditorSurface
      onClose={onClose}
      presentation={presentation}
      title={
        <>{currentId ? title || "Home" : "Keep a Home in your Life Wiki"}</>
      }
      titleId="home-editor-title"
      eyebrow={<>{currentId ? "Edit Home" : "New Home"}</>}
      closeLabel="Close Home editor"
      busy={isPending}
      footer={
        <div className={styles.dialogFooter}>
          {result ? (
            <p
              className={`${styles.formMessage} ${styles.footerMessage}`}
              role="alert"
            >
              {result.message}
            </p>
          ) : null}
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
              form="homes-workspace-form"
              variant="primary"
              disabled={isPending}
              type="submit"
            >
              {isPending
                ? "Saving..."
                : currentId
                  ? "Save changes"
                  : "Add Home"}
            </Button>
          </div>
        </div>
      }
    >
      <form id="homes-workspace-form" onSubmit={handleSubmit}>
        <div className={styles.formGrid}>
          <fieldset className={styles.formSection}>
            <legend>Home details</legend>
            <label className={styles.fullField}>
              <span>
                Home name <span aria-hidden="true">*</span>
              </span>
              <input
                aria-label="Home name"
                maxLength={homeTitleLimit}
                onChange={(event) => setTitle(event.target.value)}
                placeholder="Philadelphia rowhome"
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
            <label>
              <span>Why you moved in</span>
              <input
                maxLength={10_000}
                onChange={(event) => setMoveInReason(event.target.value)}
                value={moveInReason}
              />
            </label>
            <label>
              <span>Why you left</span>
              <input
                maxLength={10_000}
                onChange={(event) => setMoveOutReason(event.target.value)}
                value={moveOutReason}
              />
            </label>
          </fieldset>

          <fieldset className={styles.formSection}>
            <legend>Location</legend>
            <div className={styles.fullField}>
              <LocationPicker
                disabled={isPending}
                onChange={chooseLocation}
                subject="Home"
                value={location}
              />
            </div>
            <p className={styles.fullField}>
              Save an address or position for this Home. It can appear on a
              future map alongside memories and events from the same area.
            </p>
            <label>
              <span>City</span>
              <input
                maxLength={200}
                onChange={(event) =>
                  typeAddressPart(setCity, event.target.value)
                }
                value={city}
              />
            </label>
            <label>
              <span>Region</span>
              <input
                maxLength={200}
                onChange={(event) =>
                  typeAddressPart(setRegion, event.target.value)
                }
                value={region}
              />
            </label>
            <label>
              <span>Country</span>
              <input
                maxLength={200}
                onChange={(event) =>
                  typeAddressPart(setCountry, event.target.value)
                }
                value={country}
              />
            </label>
            <label>
              <span>
                Exact address <small>Private</small>
              </span>
              <input
                maxLength={500}
                onChange={(event) =>
                  typeAddressPart(setAddress, event.target.value)
                }
                value={address}
              />
            </label>
          </fieldset>

          <fieldset className={styles.formSection}>
            <legend>Memories and organization</legend>
            <label className={styles.fullField}>
              <span>Memories</span>
              <textarea
                maxLength={homeBodyLimit}
                onChange={(event) => setBody(event.target.value)}
                placeholder="What was life like here? What do you want to remember?"
                rows={5}
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
            recordLabel="Home"
          />
        </div>
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
    registerHomeAttachment,
    onProgress,
  );
}

function manualLocation(
  address: string,
  city: string,
  region: string,
  country: string,
): LocationInput | null {
  const parts = {
    address: address.trim() || null,
    city: city.trim() || null,
    region: region.trim() || null,
    country: country.trim() || null,
  };
  return Object.values(parts).some(Boolean)
    ? { kind: "manual", ...parts }
    : null;
}

/** The snapshot a save stored, so the card shows it before the page refreshes. */
function savedHomeLocation(
  input: LocationInput | null,
  savedId: string | null,
): ExistingLocation | null {
  if (!input || !savedId) return null;
  if (input.kind !== "manual") return savedLocationSelection(input, savedId);
  return {
    kind: "existing",
    id: savedId,
    revision: 1,
    formattedAddress:
      [input.address, input.city, input.region, input.country]
        .filter(Boolean)
        .join(", ") || null,
    address: input.address,
    city: input.city,
    region: input.region,
    postalCode: null,
    country: input.country,
    countryCode: null,
    latitude: null,
    longitude: null,
    timezone: null,
    resultType: null,
  };
}

function namesIncludingDraft(names: string[], draft: string) {
  const name = draft.trim();
  return name ? [...names, name] : names;
}

function localTimezone() {
  return Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
}

function actionError(message: string): HomeActionResult {
  return { entry: null, message, status: "error" };
}

function truncate(value: string, limit: number) {
  return value.length > limit ? `${value.slice(0, limit).trimEnd()}...` : value;
}
