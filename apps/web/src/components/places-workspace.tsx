"use client";
import { Dialog } from "@/components/dialog";
import { EmptyState } from "@/components/empty-state";
import { PageHeader } from "@/components/page-header";
import { Button } from "@/components/button";

import { useRef, useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import {
  savePlace,
  trashPlace,
  type PlaceActionResult,
} from "@/app/places/actions";
import common from "@/app/homes/page.module.css";
import styles from "@/app/places/page.module.css";
import { Icon } from "@/components/icon";
import { PageFrame } from "@/components/page-frame";
import { ProgressiveImage } from "@/components/progressive-image";
import {
  RecordCard,
  RecordCardBody,
  RecordCardVisual,
} from "@/components/record-card";
import {
  placeCoordinateLabel,
  placeCover,
  placeLocationLabel,
  type PlaceLinkOption,
  type PlaceLinkedEntry,
  type PlaceRecord,
} from "@/lib/data/place-record";
import {
  parsePlaceRecordInput,
  placeAddressLimit,
  placeCityLimit,
  placeCountryLimit,
  placeNameLimit,
  placeNotesLimit,
  placeRegionLimit,
  type PlaceRecordInput,
} from "@/lib/data/place-record-input";
import { wikiItemIdentityLabel } from "@/lib/data/wiki-item";

export function PlacesWorkspace({
  initialPlaceId,
  linkOptions,
  loadError,
  places,
}: {
  initialPlaceId: string | null;
  linkOptions: PlaceLinkOption[];
  loadError: string | null;
  places: PlaceRecord[];
}) {
  const router = useRouter();
  const [selectedPlace, setSelectedPlace] = useState<
    PlaceRecord | null | undefined
  >(places.find((place) => place.id === initialPlaceId));
  const linkedCount = places.filter(
    (place) => place.linkedEntryCount > 0,
  ).length;
  const mappedCount = places.filter((place) => place.latitude !== null).length;
  const remembered = places.filter((place) => place.linkedEntryCount > 0);
  const unlinked = places.filter((place) => place.linkedEntryCount === 0);

  return (
    <PageFrame variant="wide">
      <PageHeader
        title={<>Places</>}
        eyebrow={<>A geography of your archive</>}
        description={
          <>
            Keep reusable locations once, then connect them to the Items and
            Home chapters that give them meaning.
          </>
        }
        actions={
          <>
            <Button
              variant="primary"
              aria-label="Add Place"

              onClick={() => setSelectedPlace(null)}
              type="button"
            >
              <Icon name="plus" />
              <span>Add Place</span>
            </Button>
          </>
        }
      />

      <div className={common.summary} aria-label="Places summary">
        <span>{countLabel(places.length, "place")}</span>
        <span aria-hidden="true">·</span>
        <span>{linkedCount} with memories</span>
        <span aria-hidden="true">·</span>
        <span>{mappedCount} with coordinates</span>
      </div>

      {loadError ? (
        <div className={common.message} role="alert">
          <Icon name="map" size={22} />
          <div>
            <strong>Places unavailable</strong>
            <p>{loadError}</p>
          </div>
        </div>
      ) : null}

      {!loadError && places.length === 0 ? (
        <EmptyState
          title={<>Pin the first place in your story</>}
          icon={
            <>
              <Icon name="map" size={24} />
            </>
          }
          description={
            <>
              Start with a name. Address, coordinates, notes, and connected
              memories can be added whenever they become useful.
            </>
          }
          onClick={() => setSelectedPlace(null)}
        />
      ) : null}

      {!loadError && remembered.length > 0 ? (
        <PlaceSection
          detail="Locations already connected to your archive"
          onSelect={setSelectedPlace}
          places={remembered}
          title="In your story"
        />
      ) : null}

      {!loadError && unlinked.length > 0 ? (
        <PlaceSection
          detail="Saved locations waiting for their first connection"
          onSelect={setSelectedPlace}
          places={unlinked}
          title="Unlinked places"
        />
      ) : null}

      {selectedPlace !== undefined ? (
        <PlaceEditor
          key={selectedPlace?.id ?? "new-place"}
          linkOptions={linkOptions}
          onClose={() => {
            setSelectedPlace(undefined);
            if (initialPlaceId) router.replace("/places", { scroll: false });
          }}
          place={selectedPlace}
        />
      ) : null}
    </PageFrame>
  );
}

function PlaceSection({
  detail,
  onSelect,
  places,
  title,
}: {
  detail: string;
  onSelect: (place: PlaceRecord) => void;
  places: PlaceRecord[];
  title: string;
}) {
  return (
    <section className={common.homeSection}>
      <header>
        <h2>{title}</h2>
        <span>{detail}</span>
      </header>
      <div className={styles.placeGrid}>
        {places.map((place) => (
          <PlaceCard
            key={place.id}
            onSelect={() => onSelect(place)}
            place={place}
          />
        ))}
      </div>
    </section>
  );
}

function PlaceCard({
  onSelect,
  place,
}: {
  onSelect: () => void;
  place: PlaceRecord;
}) {
  const cover = placeCover(place);
  const coordinates = placeCoordinateLabel(place);
  const relatedEntries = place.linkedEntries.filter(
    (entry) => entry.relationship === "related",
  );

  return (
    <RecordCard
      ariaLabel={`${place.name}, ${placeLocationLabel(place)}`}
      className={styles.placeCard}
      onClick={onSelect}
    >
      <RecordCardVisual className={styles.placeVisual}>
        {cover?.imageUrl ? (
          <ProgressiveImage
            alt=""
            sizes="(max-width: 780px) 132px, 360px"
            src={cover.imageUrl}
          />
        ) : (
          <div className={styles.mapMark}>
            <span aria-hidden="true" />
            <Icon name="map" size={27} />
            <small>{coordinates ?? "Coordinates not added"}</small>
          </div>
        )}
        {place.homeCount > 0 ? (
          <span className={styles.homeBadge}>
            <Icon name="home" size={12} /> Home
          </span>
        ) : null}
        {cover?.imageUrl && coordinates ? (
          <small className={styles.coordinateBadge}>{coordinates}</small>
        ) : null}
      </RecordCardVisual>

      <RecordCardBody className={styles.placeBody}>
        <p className={styles.locationLine}>
          <Icon name="map" size={14} />
          <span>{placeLocationLabel(place)}</span>
        </p>
        <h3>{place.name}</h3>
        {place.notes ? <p className={styles.notes}>{place.notes}</p> : null}

        <div className={styles.entryPreview}>
          {place.linkedEntries.slice(0, 2).map((entry) => (
            <span key={`${entry.relationship}-${entry.id}`}>
              {entry.relationship === "home"
                ? "Home"
                : wikiItemIdentityLabel(entry.itemKind, entry.itemSubtype)}
              {": "}
              {entry.title}
            </span>
          ))}
          {place.linkedEntries.length > 2 ? (
            <small>+{place.linkedEntries.length - 2} more</small>
          ) : null}
        </div>

        <footer>
          <span>
            {countLabel(place.linkedEntryCount, "linked Item", "linked Items")}
          </span>
          <span>{countLabel(relatedEntries.length, "editable link")}</span>
        </footer>
      </RecordCardBody>
    </RecordCard>
  );
}

function PlaceEditor({
  linkOptions,
  onClose,
  place,
}: {
  linkOptions: PlaceLinkOption[];
  onClose: () => void;
  place: PlaceRecord | null;
}) {
  const router = useRouter();
  const nameRef = useRef<HTMLInputElement>(null);
  const protectedEntries =
    place?.linkedEntries.filter((entry) => entry.relationship !== "related") ??
    [];
  const initialRelatedIds =
    place?.linkedEntries
      .filter((entry) => entry.relationship === "related")
      .map((entry) => entry.id) ?? [];
  const [address, setAddress] = useState(place?.address ?? "");
  const [city, setCity] = useState(place?.city ?? "");
  const [country, setCountry] = useState(place?.country ?? "");
  const [currentId, setCurrentId] = useState(place?.id ?? null);
  const [currentRevision, setCurrentRevision] = useState(
    place?.revision ?? null,
  );
  const [isPending, setIsPending] = useState(false);
  const [latitude, setLatitude] = useState(place?.latitude?.toString() ?? "");
  const [longitude, setLongitude] = useState(
    place?.longitude?.toString() ?? "",
  );
  const [name, setName] = useState(place?.name ?? "");
  const [notes, setNotes] = useState(place?.notes ?? "");
  const [region, setRegion] = useState(place?.region ?? "");
  const [relatedEntryIds, setRelatedEntryIds] = useState(initialRelatedIds);
  const [result, setResult] = useState<PlaceActionResult | null>(null);
  const [selectedEntryId, setSelectedEntryId] = useState("");
  const linkedIds = new Set([
    ...relatedEntryIds,
    ...protectedEntries.map((entry) => entry.id),
  ]);
  const availableLinkOptions = linkOptions.filter(
    (option) => !linkedIds.has(option.id),
  );
  const hasPersistedLinks = (place?.linkedEntryCount ?? 0) > 0;
  const canTrash = Boolean(currentId) && !hasPersistedLinks;

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const input: PlaceRecordInput = {
      address: address || null,
      city: city || null,
      country: country || null,
      id: currentId,
      latitude: coordinateValue(latitude),
      longitude: coordinateValue(longitude),
      name,
      notes: notes || null,
      region: region || null,
      relatedEntryIds,
      revision: currentRevision,
    };
    const parsed = parsePlaceRecordInput(input);
    if (!parsed.success) {
      setResult(actionError(parsed.message));
      return;
    }

    setIsPending(true);
    setResult(null);
    try {
      const saved = await savePlace(parsed.data);
      if (
        (saved.status !== "created" && saved.status !== "saved") ||
        !saved.place
      ) {
        setResult(saved);
        return;
      }
      setCurrentId(saved.place.id);
      setCurrentRevision(saved.place.revision);
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

  async function handleTrash() {
    if (!currentId || currentRevision === null || !canTrash) return;
    if (
      !window.confirm(
        `Move “${name.trim() || "this Place"}” to Trash? Its history will be preserved.`,
      )
    ) {
      return;
    }
    setIsPending(true);
    setResult(null);
    try {
      const nextResult = await trashPlace({
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
      setResult(actionError("MemoTrail could not move this Place to Trash."));
    } finally {
      setIsPending(false);
    }
  }

  return (
    <Dialog
      open
      onOpenChange={(nextOpen) => {
        if (!nextOpen) onClose();
      }}
      title={<>{currentId ? name || "Place" : "Pin a place in your story"}</>}
      titleId="place-editor-title"
      eyebrow={<>{currentId ? "Edit Place" : "New Place"}</>}
      closeLabel="Close Place editor"
      busy={isPending}
      size="wide"
      footer={
        <div className={common.dialogFooter}>
          <div>
            {currentId ? (
              <div className={styles.trashControl}>
                <Button
                  variant="danger"

                  disabled={isPending || !canTrash}
                  onClick={() => void handleTrash()}
                  type="button"
                >
                  Move to Trash
                </Button>
                {!canTrash ? (
                  <small>
                    {protectedEntries.length > 0
                      ? "Remove its Home link first"
                      : relatedEntryIds.length === 0
                        ? "Save the unlinked Place first"
                        : "Unlink every Item first"}
                  </small>
                ) : null}
              </div>
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
              form="places-workspace-form"
              variant="primary"

              disabled={isPending}
              type="submit"
            >
              {isPending
                ? "Saving..."
                : currentId
                  ? "Save changes"
                  : "Add Place"}
            </Button>
          </div>
        </div>
      }
    >
      <form id="places-workspace-form" onSubmit={handleSubmit}>
        <div className={common.formGrid}>
          <fieldset className={common.formSection}>
            <legend>Place details</legend>
            <label className={common.fullField}>
              <span>
                Name <span aria-hidden="true">*</span>
              </span>
              <input
                aria-label="Name"
                maxLength={placeNameLimit}
                onChange={(event) => setName(event.target.value)}
                placeholder="Rittenhouse Square apartment"
                ref={nameRef}
                required
                value={name}
              />
            </label>
            <label className={common.fullField}>
              <span>Address</span>
              <input
                autoComplete="street-address"
                maxLength={placeAddressLimit}
                onChange={(event) => setAddress(event.target.value)}
                placeholder="A street address or descriptive location"
                value={address}
              />
            </label>
            <label>
              <span>City</span>
              <input
                autoComplete="address-level2"
                maxLength={placeCityLimit}
                onChange={(event) => setCity(event.target.value)}
                placeholder="Philadelphia"
                value={city}
              />
            </label>
            <label>
              <span>Region</span>
              <input
                autoComplete="address-level1"
                maxLength={placeRegionLimit}
                onChange={(event) => setRegion(event.target.value)}
                placeholder="Pennsylvania"
                value={region}
              />
            </label>
            <label className={common.fullField}>
              <span>Country</span>
              <input
                autoComplete="country-name"
                maxLength={placeCountryLimit}
                onChange={(event) => setCountry(event.target.value)}
                placeholder="United States"
                value={country}
              />
            </label>
          </fieldset>

          <fieldset className={common.formSection}>
            <legend>Map coordinates</legend>
            <label>
              <span>Latitude</span>
              <input
                inputMode="decimal"
                max="90"
                min="-90"
                onChange={(event) => setLatitude(event.target.value)}
                placeholder="39.9526"
                step="any"
                type="number"
                value={latitude}
              />
            </label>
            <label>
              <span>Longitude</span>
              <input
                inputMode="decimal"
                max="180"
                min="-180"
                onChange={(event) => setLongitude(event.target.value)}
                placeholder="-75.1652"
                step="any"
                type="number"
                value={longitude}
              />
            </label>
            <p className={`${common.fullField} ${styles.coordinateNote}`}>
              Add both values or leave both empty. Coordinates are stored now so
              this archive can support a map view later.
            </p>
          </fieldset>

          <fieldset className={common.formSection}>
            <legend>Memory</legend>
            <label className={common.fullField}>
              <span>Notes</span>
              <textarea
                maxLength={placeNotesLimit}
                onChange={(event) => setNotes(event.target.value)}
                placeholder="What makes this place worth remembering?"
                rows={5}
                value={notes}
              />
            </label>
          </fieldset>

          <fieldset
            className={`${common.formSection} ${styles.relationshipSection}`}
          >
            <legend>Connected Items</legend>
            <p className={styles.relationshipIntro}>
              Link existing Items to bring their dates, text, and private photos
              into this Place. Home links are protected here.
            </p>

            {protectedEntries.length > 0 ? (
              <div className={styles.protectedLinks}>
                <strong>Protected context</strong>
                {protectedEntries.map((entry) => (
                  <LinkedEntryRow
                    entry={entry}
                    key={`${entry.relationship}-${entry.id}`}
                  />
                ))}
              </div>
            ) : null}

            {relatedEntryIds.length > 0 ? (
              <div className={styles.editableLinks}>
                <strong>Related Items</strong>
                {relatedEntryIds.map((entryId) => {
                  const option = linkOptions.find(
                    (item) => item.id === entryId,
                  );
                  const existing = place?.linkedEntries.find(
                    (item) => item.id === entryId,
                  );
                  return (
                    <div className={styles.editableLink} key={entryId}>
                      <span>
                        <small>
                          {option
                            ? wikiItemIdentityLabel(
                                option.itemKind,
                                option.itemSubtype,
                              )
                            : existing
                              ? wikiItemIdentityLabel(
                                  existing.itemKind,
                                  existing.itemSubtype,
                                )
                              : "Item"}
                        </small>
                        {option?.title ?? existing?.title ?? "Linked Item"}
                      </span>
                      <button
                        aria-label={`Unlink ${option?.title ?? existing?.title ?? "Item"}`}
                        disabled={isPending}
                        onClick={() =>
                          setRelatedEntryIds((current) =>
                            current.filter((id) => id !== entryId),
                          )
                        }
                        type="button"
                      >
                        ×
                      </button>
                    </div>
                  );
                })}
              </div>
            ) : null}

            <div className={styles.linkPicker}>
              <select
                aria-label="Item to link"
                disabled={isPending || availableLinkOptions.length === 0}
                onChange={(event) => setSelectedEntryId(event.target.value)}
                value={selectedEntryId}
              >
                <option value="">
                  {availableLinkOptions.length > 0
                    ? "Choose an Item"
                    : "No more Items available"}
                </option>
                {availableLinkOptions.map((option) => (
                  <option key={option.id} value={option.id}>
                    {wikiItemIdentityLabel(option.itemKind, option.itemSubtype)}{" "}
                    · {option.title}
                  </option>
                ))}
              </select>
              <Button
                variant="secondary"
                disabled={!selectedEntryId || isPending}
                onClick={() => {
                  if (!selectedEntryId) return;
                  setRelatedEntryIds((current) => [
                    ...current,
                    selectedEntryId,
                  ]);
                  setSelectedEntryId("");
                }}
                type="button"
              >
                <Icon name="plus" size={14} /> Link Item
              </Button>
            </div>
          </fieldset>
        </div>

        {result ? (
          <p className={common.formMessage} role="alert">
            {result.message}
          </p>
        ) : null}
      </form>
    </Dialog>
  );
}

function LinkedEntryRow({ entry }: { entry: PlaceLinkedEntry }) {
  return (
    <div className={styles.protectedLink}>
      <span className={styles.protectedIcon}>
        <Icon name="home" size={14} />
      </span>
      <span>
        <small>
          {entry.relationship === "home"
            ? "Home chapter"
            : wikiItemIdentityLabel(entry.itemKind, entry.itemSubtype)}
        </small>
        {entry.title}
      </span>
      <small>Managed from its record</small>
    </div>
  );
}

function coordinateValue(value: string) {
  const normalized = value.trim();
  return normalized ? Number(normalized) : null;
}

function countLabel(count: number, singular: string, plural = `${singular}s`) {
  return `${count} ${count === 1 ? singular : plural}`;
}

function actionError(message: string): PlaceActionResult {
  return { message, place: null, status: "error" };
}
