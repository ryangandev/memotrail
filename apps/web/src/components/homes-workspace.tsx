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
import { Icon } from "@/components/icon";
import {
  createFirstTimeObjectPath,
  firstTimePhotoLimit,
  firstTimePhotoSizeLimit,
  inferFirstTimeImageMimeType,
} from "@/lib/data/first-time-input";
import {
  homeBodyLimit,
  homeDatePrecisions,
  homeLabelLimit,
  homePlaceNameLimit,
  homeTitleLimit,
  parseHomeEntryInput,
  type HomeDatePrecision,
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
import {
  localDateToISOString,
  localDateValue,
} from "@/lib/data/timeline-input";
import { createClient } from "@/lib/supabase/client";

const precisionLabels: Record<HomeDatePrecision, string> = {
  age: "Age-based",
  approximate: "Approximate",
  day: "Exact day",
  exact: "Exact date and time",
  month: "Month and year",
  range: "Date range",
  year: "Year",
};

export function HomesWorkspace({
  collectionOptions,
  homes,
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

function HomeEditor({
  collectionOptions,
  home,
  onClose,
  ownerId,
  placeOptions,
  tagOptions,
}: {
  collectionOptions: string[];
  home: HomeRecord | null;
  onClose: () => void;
  ownerId: string;
  placeOptions: HomePlaceOption[];
  tagOptions: string[];
}) {
  const router = useRouter();
  const titleRef = useRef<HTMLInputElement>(null);
  const initialTimezone = home?.occurredTimezone ?? localTimezone();
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
  const [datePrecision, setDatePrecision] = useState<HomeDatePrecision>(
    editablePrecision(home?.datePrecision),
  );
  const [existingPhotos, setExistingPhotos] = useState(home?.attachments ?? []);
  const [isPending, setIsPending] = useState(false);
  const [latitude, setLatitude] = useState(home?.latitude?.toString() ?? "");
  const [longitude, setLongitude] = useState(home?.longitude?.toString() ?? "");
  const [moveInDate, setMoveInDate] = useState(
    home ? localDateValue(home.occurredStart, initialTimezone) : "",
  );
  const [moveInReason, setMoveInReason] = useState(home?.moveInReason ?? "");
  const [moveOutDate, setMoveOutDate] = useState(
    home?.occurredEnd ? localDateValue(home.occurredEnd, initialTimezone) : "",
  );
  const [moveOutReason, setMoveOutReason] = useState(home?.moveOutReason ?? "");
  const [occurredLabel, setOccurredLabel] = useState(home?.occurredLabel ?? "");
  const [occurredTimezone] = useState(initialTimezone);
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
    const occurredStart = moveInDate
      ? localDateToISOString(moveInDate, occurredTimezone)
      : null;
    const occurredEnd = moveOutDate
      ? localDateToISOString(moveOutDate, occurredTimezone)
      : null;
    const input: HomeEntryInput = {
      address: address || null,
      body,
      city: city || null,
      collectionNames: namesIncludingDraft(collectionNames, collectionInput),
      country: country || null,
      datePrecision,
      id: currentId,
      latitude: coordinateValue(latitude),
      longitude: coordinateValue(longitude),
      moveInReason: moveInReason || null,
      moveOutReason: moveOutReason || null,
      occurredEnd: occurredEnd ?? (moveOutDate || null),
      occurredLabel: occurredLabel || null,
      occurredStart: occurredStart ?? moveInDate,
      occurredTimezone,
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
              <label>
                <span>Move-in date</span>
                <input
                  onChange={(event) => setMoveInDate(event.target.value)}
                  required
                  type="date"
                  value={moveInDate}
                />
              </label>
              <label>
                <span>
                  Move-out date <small>Leave empty if current</small>
                </span>
                <input
                  min={moveInDate || undefined}
                  onChange={(event) => setMoveOutDate(event.target.value)}
                  type="date"
                  value={moveOutDate}
                />
              </label>
              <label>
                <span>Date precision</span>
                <select
                  onChange={(event) =>
                    setDatePrecision(event.target.value as HomeDatePrecision)
                  }
                  value={datePrecision}
                >
                  {homeDatePrecisions.map((precision) => (
                    <option key={precision} value={precision}>
                      {precisionLabels[precision]}
                    </option>
                  ))}
                </select>
              </label>
              <label>
                <span>
                  Human date label <small>Optional</small>
                </span>
                <input
                  maxLength={homeLabelLimit}
                  onChange={(event) => setOccurredLabel(event.target.value)}
                  placeholder="Ages 12 to 25"
                  value={occurredLabel}
                />
              </label>
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
                  disabled={!moveOutDate}
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
  const datalistId = `home-${label.toLocaleLowerCase()}-options`;
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
      console.warn("Home photo upload failed:", upload.error.message);
      failed.push(photo);
      continue;
    }

    const registered = await registerHomeAttachment({
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
      console.warn("Home photo registration failed:", registered.message);
      await client.storage.from("entry-media").remove([objectPath]);
      failed.push(photo);
    }
  }

  return failed;
}

function editablePrecision(value: HomeDatePrecision | undefined) {
  return value === "exact" ? "day" : (value ?? "month");
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
