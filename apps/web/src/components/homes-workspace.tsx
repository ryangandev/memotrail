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
  registerHomeAttachment,
  saveHomeEntry,
  trashHomeAttachment,
  trashHomeEntry,
  type HomeActionResult,
} from "@/app/homes/actions";
import styles from "@/app/homes/page.module.css";
import { EntryOrganizationEditor } from "@/components/entry-organization-editor";
import { Icon } from "@/components/icon";
import {
  firstTimePhotoLimit,
  firstTimePhotoSizeLimit,
  inferFirstTimeImageMimeType,
} from "@/lib/data/first-time-input";
import {
  homeBodyLimit,
  homePlaceNameLimit,
  homeTitleLimit,
  parseHomeEntryInput,
  type HomeEntryInput,
} from "@/lib/data/home-record-input";
import {
  homeDurationLabel,
  homeLocationLabel,
  homeRangeLabel,
  type HomeAttachment,
  type HomePlaceOption,
  type HomeRecord,
} from "@/lib/data/home-record";
import { OccurrenceEditor } from "@/components/occurrence-editor";
import {
  occurrenceDraft,
  resolveOccurrenceDraft,
  type Occurrence,
} from "@/lib/data/occurrence";
import { useConfirmedRecords } from "@/components/use-confirmed-records";
import { uploadEntryPhotos } from "@/lib/media/upload";

export function HomesWorkspace({
  collectionOptions,
  homes: serverRecords,
  initialHomeId,
  loadError,
  ownerId,
  placeOptions,
  tagOptions,
}: {
  collectionOptions: string[];
  homes: HomeRecord[];
  initialHomeId: string | null;
  loadError: string | null;
  ownerId: string;
  placeOptions: HomePlaceOption[];
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
  >(homes.find((home) => home.id === initialHomeId));
  const currentHomes = homes.filter((home) => !home.occurredEnd);
  const earlierHomes = homes.filter((home) => home.occurredEnd);

  return (
    <div className={styles.content}>
      <header className={styles.pageHeader}>
        <div>
          <p className={styles.eyebrow}>The places that held your life</p>
          <h1>Homes</h1>
          <p>
            Keep each residence as a chapter, from the rough dates to the
            memories that made it yours.
          </p>
        </div>
        <button
          aria-label="Add Home"
          className={styles.addButton}
          onClick={() => setSelectedHome(null)}
          type="button"
        >
          <Icon name="plus" />
          <span>Add Home</span>
        </button>
      </header>

      <div className={styles.summary} aria-label="Homes summary">
        <span>{countLabel(homes.length, "home")}</span>
        <span aria-hidden="true">·</span>
        <span>{countLabel(currentHomes.length, "current residence")}</span>
        <span aria-hidden="true">·</span>
        <span>{countLabel(earlierHomes.length, "earlier home")}</span>
      </div>

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
        <button
          className={styles.emptyState}
          onClick={() => setSelectedHome(null)}
          type="button"
        >
          <span className={styles.emptyMark}>
            <Icon name="home" size={24} />
          </span>
          <strong>Begin with somewhere you called home</strong>
          <span>
            Add the best-known move-in date now. Exact addresses, reasons,
            photos, and memories can come later.
          </span>
        </button>
      ) : null}

      {!loadError && currentHomes.length > 0 ? (
        <HomeSection
          homes={currentHomes}
          label="Where life is happening now"
          onSelect={setSelectedHome}
          title="Current"
        />
      ) : null}

      {!loadError && earlierHomes.length > 0 ? (
        <HomeSection
          homes={earlierHomes}
          label="Chapters that came before"
          onSelect={setSelectedHome}
          title="Earlier homes"
        />
      ) : null}

      {selectedHome !== undefined ? (
        <HomeEditor
          collectionOptions={collectionOptions}
          home={selectedHome}
          key={selectedHome?.id ?? "new-home"}
          onSaved={confirm}
          onTrashed={forget}
          onClose={() => {
            setSelectedHome(undefined);
            if (initialHomeId) router.replace("/homes", { scroll: false });
          }}
          ownerId={ownerId}
          placeOptions={placeOptions}
          tagOptions={tagOptions}
        />
      ) : null}
    </div>
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
        {homes.map((home) => (
          <HomeCard home={home} key={home.id} onSelect={() => onSelect(home)} />
        ))}
      </div>
    </section>
  );
}

function HomeCard({
  home,
  onSelect,
}: {
  home: HomeRecord;
  onSelect: () => void;
}) {
  const cover = home.attachments[0];

  return (
    <button
      aria-label={`${home.title}, ${homeRangeLabel(home)}`}
      className={styles.homeCard}
      onClick={onSelect}
      type="button"
    >
      <div className={styles.homeVisual}>
        {cover?.imageUrl ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img alt="" src={cover.imageUrl} />
        ) : (
          <div className={styles.homeMark}>
            <Icon name="home" size={24} />
            <span>{home.city ?? home.country ?? "A place in your trail"}</span>
          </div>
        )}
        <span
          className={home.occurredEnd ? styles.pastBadge : styles.currentBadge}
        >
          {home.occurredEnd ? "Earlier" : "Current"}
        </span>
        {home.attachments.length > 1 ? (
          <small>{home.attachments.length} photos</small>
        ) : null}
      </div>

      <div className={styles.cardBody}>
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
            {home.collectionNames.slice(0, 2).map((name) => (
              <span key={`collection:${name.toLocaleLowerCase()}`}>{name}</span>
            ))}
            {home.tagNames.slice(0, 2).map((name) => (
              <span key={`tag:${name.toLocaleLowerCase()}`}>#{name}</span>
            ))}
          </div>
          <Icon name="chevron" size={15} />
        </footer>
      </div>
    </button>
  );
}

export function HomeEditor({
  collectionOptions,
  defaultTimezone,
  home,
  onClose,
  onSaved,
  onTrashed,
  ownerId,
  placeOptions,
  tagOptions,
}: {
  collectionOptions: string[];
  defaultTimezone?: string;
  home: HomeRecord | null;
  onClose: () => void;
  onSaved: (record: HomeRecord) => void;
  onTrashed: (id: string) => void;
  ownerId: string;
  placeOptions: HomePlaceOption[];
  tagOptions: string[];
}) {
  const router = useRouter();
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
  const [address, setAddress] = useState(home?.address ?? "");
  const [body, setBody] = useState(home?.body ?? "");
  const [city, setCity] = useState(home?.city ?? "");
  const [collectionInput, setCollectionInput] = useState("");
  const [collectionNames, setCollectionNames] = useState(
    home?.collectionNames ?? [],
  );
  const [country, setCountry] = useState(home?.country ?? "");
  const [currentId, setCurrentId] = useState(home?.id ?? null);
  const [currentRevision, setCurrentRevision] = useState(
    home?.revision ?? null,
  );
  const [existingPhotos, setExistingPhotos] = useState(home?.attachments ?? []);
  const [isPending, setIsPending] = useState(false);
  const [latitude, setLatitude] = useState(home?.latitude?.toString() ?? "");
  const [longitude, setLongitude] = useState(home?.longitude?.toString() ?? "");
  const [moveInReason, setMoveInReason] = useState(home?.moveInReason ?? "");
  const [moveOutReason, setMoveOutReason] = useState(home?.moveOutReason ?? "");
  const [pendingPhotos, setPendingPhotos] = useState<File[]>([]);
  const [placeId, setPlaceId] = useState(home?.placeId ?? null);
  const [placeName, setPlaceName] = useState(home?.placeName ?? "");
  const [placeNotes, setPlaceNotes] = useState(home?.placeNotes ?? "");
  const [region, setRegion] = useState(home?.region ?? "");
  const [result, setResult] = useState<HomeActionResult | null>(null);
  const [tagInput, setTagInput] = useState("");
  const [tagNames, setTagNames] = useState(home?.tagNames ?? []);
  const [title, setTitle] = useState(home?.title ?? "");

  useEffect(() => {
    titleRef.current?.focus();
  }, []);

  useEffect(() => {
    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape" && !isPending) {
        onClose();
      }
    }

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [isPending, onClose]);

  function selectPlace(nextId: string) {
    if (!nextId) {
      setPlaceId(null);
      setPlaceName("");
      setAddress("");
      setCity("");
      setRegion("");
      setCountry("");
      setLatitude("");
      setLongitude("");
      setPlaceNotes("");
      return;
    }

    const place = placeOptions.find((option) => option.id === nextId);
    if (!place) return;

    setPlaceId(place.id);
    setPlaceName(place.name);
    setAddress(place.address ?? "");
    setCity(place.city ?? "");
    setRegion(place.region ?? "");
    setCountry(place.country ?? "");
    setLatitude(place.latitude?.toString() ?? "");
    setLongitude(place.longitude?.toString() ?? "");
    setPlaceNotes(place.notes ?? "");
  }

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
      address: address || null,
      body,
      city: city || null,
      collectionNames: namesIncludingDraft(collectionNames, collectionInput),
      country: country || null,
      datePrecision: resolved.value.datePrecision,
      id: currentId,
      latitude: coordinateValue(latitude),
      longitude: coordinateValue(longitude),
      moveInReason: moveInReason || null,
      moveOutReason: moveOutReason || null,
      occurredEnd: resolved.value.occurredEnd,
      occurredLabel: resolved.value.occurredLabel,
      occurredStart: resolved.value.occurredAt,
      occurredTimezone: resolved.value.occurredTimezone,
      placeId,
      placeName,
      placeNotes: placeNotes || null,
      region: region || null,
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
      const saved = await saveHomeEntry(parsed.data);
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
        timelineTrackId: home?.timelineTrackId ?? null,
        timelineTrackName: home?.timelineTrackName ?? "Homes",
        totalCount: home?.totalCount ?? 1,
        updatedAt: new Date().toISOString(),
      });
      setCurrentId(saved.entry.id);
      setCurrentRevision(saved.entry.revision);
      setPlaceId(saved.entry.placeId);
      const failedPhotos = await uploadPhotos(
        ownerId,
        saved.entry.id,
        pendingPhotos,
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

  async function handleRemovePhoto(photo: HomeAttachment) {
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
      const nextResult = await trashHomeAttachment({ attachmentId: photo.id });
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
        `Move “${title.trim() || "this Home"}” to Trash? Its history, Place, and private photos will be preserved.`,
      )
    ) {
      return;
    }

    setIsPending(true);
    setResult(null);
    try {
      const nextResult = await trashHomeEntry({
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
      setResult(actionError("MemoTrail could not move this Home to Trash."));
    } finally {
      setIsPending(false);
    }
  }

  return (
    <div
      aria-labelledby="home-editor-title"
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
            <p>{currentId ? "Edit Home" : "New Home"}</p>
            <h2 id="home-editor-title">
              {currentId ? title || "Home" : "Keep a place in your story"}
            </h2>
          </div>
          <button
            aria-label="Close Home editor"
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
              <legend>Home chapter</legend>
              <label className={styles.fullField}>
                <span>Home name</span>
                <input
                  maxLength={homeTitleLimit}
                  onChange={(event) => setTitle(event.target.value)}
                  placeholder="Philadelphia rowhome"
                  ref={titleRef}
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
                <span>
                  Why you moved in <small>Optional</small>
                </span>
                <input
                  maxLength={10_000}
                  onChange={(event) => setMoveInReason(event.target.value)}
                  value={moveInReason}
                />
              </label>
              <label>
                <span>
                  Why you left <small>Optional</small>
                </span>
                <input
                  maxLength={10_000}
                  onChange={(event) => setMoveOutReason(event.target.value)}
                  value={moveOutReason}
                />
              </label>
            </fieldset>

            <fieldset className={styles.formSection}>
              <legend>Place</legend>
              {placeOptions.length > 0 ? (
                <label className={styles.fullField}>
                  <span>
                    Saved Place <small>Optional</small>
                  </span>
                  <select
                    onChange={(event) => selectPlace(event.target.value)}
                    value={placeId ?? ""}
                  >
                    <option value="">Create a new Place</option>
                    {placeOptions.map((place) => (
                      <option key={place.id} value={place.id}>
                        {place.name}
                      </option>
                    ))}
                  </select>
                  <small>
                    Editing a saved Place updates it anywhere it is reused.
                  </small>
                </label>
              ) : null}
              <label className={styles.fullField}>
                <span>Place name</span>
                <input
                  maxLength={homePlaceNameLimit}
                  onChange={(event) => setPlaceName(event.target.value)}
                  placeholder="The house on Pine Street"
                  value={placeName}
                />
              </label>
              <label>
                <span>
                  City <small>Optional</small>
                </span>
                <input
                  maxLength={200}
                  onChange={(event) => setCity(event.target.value)}
                  value={city}
                />
              </label>
              <label>
                <span>
                  Region <small>Optional</small>
                </span>
                <input
                  maxLength={200}
                  onChange={(event) => setRegion(event.target.value)}
                  value={region}
                />
              </label>
              <label>
                <span>
                  Country <small>Optional</small>
                </span>
                <input
                  maxLength={200}
                  onChange={(event) => setCountry(event.target.value)}
                  value={country}
                />
              </label>
              <label>
                <span>
                  Exact address <small>Private and optional</small>
                </span>
                <input
                  maxLength={500}
                  onChange={(event) => setAddress(event.target.value)}
                  value={address}
                />
              </label>
              <label>
                <span>
                  Latitude <small>Optional</small>
                </span>
                <input
                  onChange={(event) => setLatitude(event.target.value)}
                  step="any"
                  type="number"
                  value={latitude}
                />
              </label>
              <label>
                <span>
                  Longitude <small>Optional</small>
                </span>
                <input
                  onChange={(event) => setLongitude(event.target.value)}
                  step="any"
                  type="number"
                  value={longitude}
                />
              </label>
              <label className={styles.fullField}>
                <span>
                  Place notes <small>Optional</small>
                </span>
                <textarea
                  maxLength={10_000}
                  onChange={(event) => setPlaceNotes(event.target.value)}
                  placeholder="Neighborhood, what was nearby, or anything about the place itself."
                  rows={3}
                  value={placeNotes}
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
                  maxLength={homeBodyLimit}
                  onChange={(event) => setBody(event.target.value)}
                  placeholder="What was life like here? What do you want to remember?"
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
                        // eslint-disable-next-line @next/next/no-img-element
                        <img
                          alt={photo.originalFilename ?? "Home photo"}
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
                    : "Add Home"}
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
  return uploadEntryPhotos(ownerId, entryId, photos, registerHomeAttachment);
}

function namesIncludingDraft(names: string[], draft: string) {
  const name = draft.trim();
  return name ? [...names, name] : names;
}

function coordinateValue(value: string) {
  return value.trim() ? Number(value) : null;
}

function localTimezone() {
  return Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
}

function actionError(message: string): HomeActionResult {
  return { entry: null, message, status: "error" };
}

function countLabel(count: number, singular: string) {
  return `${count} ${count === 1 ? singular : `${singular}s`}`;
}

function truncate(value: string, limit: number) {
  return value.length > limit ? `${value.slice(0, limit).trimEnd()}...` : value;
}
