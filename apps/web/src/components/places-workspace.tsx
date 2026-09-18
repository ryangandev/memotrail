"use client";

import { useRef, useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import {
  savePlace,
  trashPlace,
  type PlaceActionResult,
} from "@/app/places/actions";
import { Button } from "@/components/button";
import { useConfirmationDialog } from "@/components/confirmation-dialog";
import { Dialog } from "@/components/dialog";
import { EmptyState } from "@/components/empty-state";
import { FocusedViewLayout } from "@/components/focused-view-layout";
import { Icon } from "@/components/icon";
import {
  RecordCard,
  RecordCardBody,
  RecordCardVisual,
} from "@/components/record-card";
import common from "@/components/record-workspace.module.css";
import styles from "@/components/places-workspace.module.css";
import { placeLocationLabel, type PlaceRecord } from "@/lib/data/place-record";
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

export function PlacesWorkspace({
  initialPlaceId,
  loadError,
  places,
}: {
  initialPlaceId: string | null;
  loadError: string | null;
  places: PlaceRecord[];
}) {
  const router = useRouter();
  const [selectedPlace, setSelectedPlace] = useState<
    PlaceRecord | null | undefined
  >(places.find((place) => place.id === initialPlaceId));

  return (
    <FocusedViewLayout
      actions={
        <Button
          variant="primary"
          aria-label="Add Place"
          onClick={() => setSelectedPlace(null)}
          type="button"
        >
          <Icon name="plus" />
          <span>Add Place</span>
        </Button>
      }
      description={
        <>Save the personally meaningful places you want to remember.</>
      }
      eyebrow={<>Personal landmarks in your story</>}
      summary={<span>{countLabel(places.length, "place")}</span>}
      summaryLabel="Places summary"
      title={<>Places</>}
    >
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
          title={<>Remember your first Place</>}
          icon={<Icon name="map" size={24} />}
          description={
            <>
              A Place is a small personal record, not a copy of an Entry or a
              Home. Start with a name and add only the context worth keeping.
            </>
          }
          onClick={() => setSelectedPlace(null)}
        />
      ) : null}

      {!loadError && places.length > 0 ? (
        <section className={common.homeSection}>
          <header>
            <h2>Saved Places</h2>
            <span>Independent personal records</span>
          </header>
          <div className={styles.placeGrid}>
            {places.map((place) => (
              <PlaceCard
                key={place.id}
                onSelect={() => setSelectedPlace(place)}
                place={place}
              />
            ))}
          </div>
        </section>
      ) : null}

      {selectedPlace !== undefined ? (
        <PlaceEditor
          key={selectedPlace?.id ?? "new-place"}
          onClose={() => {
            setSelectedPlace(undefined);
            if (initialPlaceId) router.replace("/places", { scroll: false });
          }}
          place={selectedPlace}
        />
      ) : null}
    </FocusedViewLayout>
  );
}

function PlaceCard({
  onSelect,
  place,
}: {
  onSelect: () => void;
  place: PlaceRecord;
}) {
  return (
    <RecordCard
      ariaLabel={`${place.name}, ${placeLocationLabel(place)}`}
      className={styles.placeCard}
      onClick={onSelect}
    >
      <RecordCardVisual className={styles.placeVisual}>
        <div className={styles.mapMark}>
          <span aria-hidden="true" />
          <Icon name="map" size={27} />
        </div>
      </RecordCardVisual>
      <RecordCardBody className={styles.placeBody}>
        <p className={styles.locationLine}>
          <Icon name="map" size={14} />
          <span>{placeLocationLabel(place)}</span>
        </p>
        <h3>{place.name}</h3>
        {place.notes ? <p className={styles.notes}>{place.notes}</p> : null}
        <footer>
          <span>Personal Place</span>
        </footer>
      </RecordCardBody>
    </RecordCard>
  );
}

function PlaceEditor({
  onClose,
  place,
}: {
  onClose: () => void;
  place: PlaceRecord | null;
}) {
  const router = useRouter();
  const requestConfirmation = useConfirmationDialog();
  const nameRef = useRef<HTMLInputElement>(null);
  const [address, setAddress] = useState(place?.address ?? "");
  const [city, setCity] = useState(place?.city ?? "");
  const [country, setCountry] = useState(place?.country ?? "");
  const [currentId, setCurrentId] = useState(place?.id ?? null);
  const [currentRevision, setCurrentRevision] = useState(
    place?.revision ?? null,
  );
  const [isPending, setIsPending] = useState(false);
  const [name, setName] = useState(place?.name ?? "");
  const [notes, setNotes] = useState(place?.notes ?? "");
  const [region, setRegion] = useState(place?.region ?? "");
  const [result, setResult] = useState<PlaceActionResult | null>(null);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const input: PlaceRecordInput = {
      address: address || null,
      city: city || null,
      country: country || null,
      id: currentId,
      latitude: place?.latitude ?? null,
      longitude: place?.longitude ?? null,
      name,
      notes: notes || null,
      region: region || null,
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
    if (!currentId || currentRevision === null) return;
    const confirmed = await requestConfirmation({
      title: <>Move “{name.trim() || "this Place"}” to Trash?</>,
      description: <>Its edit history will remain available for recovery.</>,
      confirmLabel: "Move to Trash",
      eyebrow: <>Recoverable action</>,
      variant: "danger",
    });
    if (!confirmed) return;
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
      title={<>{currentId ? name || "Place" : "Remember a Place"}</>}
      titleId="place-editor-title"
      eyebrow={<>{currentId ? "Edit Place" : "New Place"}</>}
      closeLabel="Close Place editor"
      busy={isPending}
      size="wide"
      footer={
        <div className={common.dialogFooter}>
          <div>
            {currentId ? (
              <Button
                variant="danger"
                disabled={isPending}
                onClick={() => void handleTrash()}
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
                placeholder="The corner café"
                ref={nameRef}
                required
                value={name}
              />
            </label>
            <label className={common.fullField}>
              <span>Address or description</span>
              <input
                maxLength={placeAddressLimit}
                onChange={(event) => setAddress(event.target.value)}
                placeholder="A street address or a description you recognize"
                value={address}
              />
            </label>
            <label>
              <span>City</span>
              <input
                maxLength={placeCityLimit}
                onChange={(event) => setCity(event.target.value)}
                value={city}
              />
            </label>
            <label>
              <span>Region</span>
              <input
                maxLength={placeRegionLimit}
                onChange={(event) => setRegion(event.target.value)}
                value={region}
              />
            </label>
            <label className={common.fullField}>
              <span>Country</span>
              <input
                maxLength={placeCountryLimit}
                onChange={(event) => setCountry(event.target.value)}
                value={country}
              />
            </label>
          </fieldset>
          <fieldset className={common.formSection}>
            <legend>Memory</legend>
            <label className={common.fullField}>
              <span>Notes</span>
              <textarea
                maxLength={placeNotesLimit}
                onChange={(event) => setNotes(event.target.value)}
                placeholder="What makes this Place worth remembering?"
                rows={5}
                value={notes}
              />
            </label>
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

function countLabel(count: number, singular: string, plural = `${singular}s`) {
  return `${count} ${count === 1 ? singular : plural}`;
}

function actionError(message: string): PlaceActionResult {
  return { message, place: null, status: "error" };
}
