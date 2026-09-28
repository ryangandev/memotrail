"use client";
import { notify } from "@/components/app-toast";
import { Dialog } from "@/components/dialog";
import { useConfirmationDialog } from "@/components/confirmation-dialog";
import { PageHeader } from "@/components/page-header";
import { Button } from "@/components/button";

import Link from "next/link";
import dynamic from "next/dynamic";
import {
  useEffect,
  useMemo,
  useRef,
  useState,
  type CSSProperties,
  type FormEvent,
} from "react";
import { useRouter } from "next/navigation";
import {
  saveTimelineEntry,
  trashTimelineEntry,
  type TimelineActionResult,
} from "@/app/timeline/actions";
import { saveBirthDate } from "@/app/settings/actions";
import { Icon } from "@/components/icon";
import { DatePickerField } from "@/components/date-picker-field";
import { EntryOrganizationEditor } from "@/components/entry-organization-editor";
import { PageFrame } from "@/components/page-frame";
import { StickyYear } from "@/components/timeline/sticky-year";
import { VerticalSpine } from "@/components/timeline/vertical-spine";
import type { FirstTimeEntry } from "@/lib/data/first-times";
import type { HomeRecord } from "@/lib/data/home-record";
import type { TimelineEntry, TimelineTrack } from "@/lib/data/timeline";
import type { VehicleRecord } from "@/lib/data/vehicle-record";
import {
  parseTimelineEntryInput,
  timelineBodyLimit,
  timelineTitleLimit,
  type TimelineEntryInput,
  type TimelineKind,
} from "@/lib/data/timeline-input";
import { createTimelineLayout } from "@/lib/data/timeline-layout";
import {
  createTimelineDisplayModel,
  timelineEntryDateLabel,
} from "@/lib/data/timeline-presentation";
import type { TimelineStyle } from "@/lib/timeline-style";
import styles from "@/components/timeline-workspace.module.css";

import { OccurrenceEditor } from "@/components/occurrence-editor";
import {
  occurrenceDraft,
  resolveOccurrenceDraft,
  type Occurrence,
} from "@/lib/data/occurrence";

const FirstTimeEditor = dynamic(
  () =>
    import("@/components/first-times-workspace").then(
      (module) => module.FirstTimeEditor,
    ),
  { loading: () => <EditorLoading /> },
);
const HomeEditor = dynamic(
  () =>
    import("@/components/homes-workspace").then((module) => module.HomeEditor),
  { loading: () => <EditorLoading /> },
);
const VehicleEditor = dynamic(
  () =>
    import("@/components/vehicles-workspace").then(
      (module) => module.VehicleEditor,
    ),
  { loading: () => <EditorLoading /> },
);

type EditorSelection =
  | { type: "chooser" }
  | {
      type: "timeline";
      entry: TimelineEntry | null;
      initialTrackId: string | null;
    }
  | { type: "home"; entry: HomeRecord | null }
  | { type: "vehicle"; entry: VehicleRecord | null }
  | { type: "first-time"; entry: FirstTimeEntry | null };

type CreationType = "moment" | "home" | "vehicle" | "first-time";

type PositionedStyle = CSSProperties & {
  "--item-lane": number;
  "--item-left": string;
  "--item-stage-label-offset": string;
  "--item-width": string;
};

type GridStyle = CSSProperties & {
  "--timeline-canvas-width": string;
  "--timeline-today-offset": string;
};

export function TimelineWorkspace({
  birthDate: serverBirthDate,
  birthDateAvailable,
  collectionOptions,
  defaultTimezone,
  firstTimes,
  homes,
  initialCreate = false,
  initialEntryId = null,
  loadError,
  ownerId,
  referenceDate,
  tagOptions,
  timelineStyle,
  tracks: serverTracks,
  vehicles,
}: {
  birthDate: string | null;
  birthDateAvailable: boolean;
  collectionOptions: string[];
  defaultTimezone: string;
  firstTimes: FirstTimeEntry[];
  homes: HomeRecord[];
  initialCreate?: boolean;
  initialEntryId?: string | null;
  loadError: string | null;
  ownerId: string;
  referenceDate: string;
  tagOptions: string[];
  timelineStyle: TimelineStyle;
  tracks: TimelineTrack[];
  vehicles: VehicleRecord[];
}) {
  const router = useRouter();
  const [selection, setSelection] = useState<EditorSelection | null>(() => {
    if (initialCreate) return { type: "chooser" };
    if (!initialEntryId) return null;
    const item = serverTracks
      .flatMap((track) => track.items)
      .find((entry) => entry.id === initialEntryId);
    if (!item) return null;
    if (item.itemKind === "entity" && item.itemSubtype === "home") {
      const home = homes.find((entry) => entry.id === initialEntryId);
      return home ? { type: "home", entry: home } : null;
    }
    if (item.itemKind === "entity" && item.itemSubtype === "vehicle") {
      const vehicle = vehicles.find((entry) => entry.id === initialEntryId);
      return vehicle ? { type: "vehicle", entry: vehicle } : null;
    }
    if (item.itemKind === "entry" && item.itemSubtype === "first_time") {
      const firstTime = firstTimes.find((entry) => entry.id === initialEntryId);
      return firstTime ? { type: "first-time", entry: firstTime } : null;
    }
    return { type: "timeline", entry: item, initialTrackId: null };
  });
  const [birthDate, setBirthDate] = useState(serverBirthDate);
  const [showBirthDatePrompt, setShowBirthDatePrompt] = useState(
    birthDateAvailable && serverBirthDate === null && loadError === null,
  );
  const [confirmed, setConfirmed] = useState<Map<string, TimelineEntry>>(
    () => new Map(),
  );
  const [previousTracks, setPreviousTracks] = useState(serverTracks);
  if (previousTracks !== serverTracks) {
    setPreviousTracks(serverTracks);
    setConfirmed((current) => {
      const next = new Map(current);
      for (const entry of serverTracks.flatMap((track) => track.items)) {
        const saved = next.get(entry.id);
        if (saved && entry.revision >= saved.revision) next.delete(entry.id);
      }
      return next.size === current.size ? current : next;
    });
  }
  const tracks = useMemo(
    () =>
      serverTracks.map((track) => {
        const entries = new Map(track.items.map((entry) => [entry.id, entry]));
        for (const saved of confirmed.values()) {
          const serverEntry = serverTracks
            .flatMap((item) => item.items)
            .find((entry) => entry.id === saved.id);
          if (serverEntry && serverEntry.revision >= saved.revision) continue;
          entries.delete(saved.id);
          if (saved.trackId === track.id) entries.set(saved.id, saved);
        }
        return { ...track, items: [...entries.values()] };
      }),
    [serverTracks, confirmed],
  );
  const items = useMemo(() => tracks.flatMap((track) => track.items), [tracks]);
  const displayModel = useMemo(
    () => createTimelineDisplayModel(tracks),
    [tracks],
  );
  const layout = useMemo(
    () => createTimelineLayout(items, new Date(referenceDate), birthDate),
    [birthDate, items, referenceDate],
  );
  const positions = useMemo(
    () => new Map(layout.positions.map((position) => [position.id, position])),
    [layout.positions],
  );
  const gridStyle: GridStyle = {
    "--timeline-canvas-width": `${layout.canvasWidth}px`,
    "--timeline-today-offset": `${(layout.todayPercent / 100) * layout.canvasWidth}px`,
  };

  function startCreation(type: CreationType, initialTrackId: string | null) {
    if (type === "home") {
      setSelection({ type: "home", entry: null });
      return;
    }
    if (type === "vehicle") {
      setSelection({ type: "vehicle", entry: null });
      return;
    }
    if (type === "first-time") {
      setSelection({ type: "first-time", entry: null });
      return;
    }
    setSelection({ type: "timeline", entry: null, initialTrackId });
  }

  function closeSelection() {
    setSelection(null);
    if (initialEntryId || initialCreate)
      router.replace("/timeline", { scroll: false });
  }

  function startCreationForTrack(track: TimelineTrack) {
    if (track.systemKey === "homes") {
      startCreation("home", track.id);
      return;
    }
    if (track.systemKey === "vehicles") {
      startCreation("vehicle", track.id);
      return;
    }
    if (track.systemKey === "first_times") {
      startCreation("first-time", track.id);
      return;
    }
    startCreation("moment", track.id);
  }

  function openEntry(entry: TimelineEntry) {
    if (entry.itemKind === "entity" && entry.itemSubtype === "home") {
      router.push(`/homes/${entry.id}`);
      return;
    }
    if (entry.itemKind === "entity" && entry.itemSubtype === "vehicle") {
      router.push(`/vehicles/${entry.id}`);
      return;
    }
    if (entry.itemKind === "entry" && entry.itemSubtype === "first_time") {
      router.push(`/first-times/${entry.id}`);
      return;
    }
    setSelection({ type: "timeline", entry, initialTrackId: null });
  }

  function renderAlternativeTimeline() {
    if (items.length === 0) {
      return (
        <TimelineEmptyState onAdd={() => setSelection({ type: "chooser" })} />
      );
    }
    return timelineStyle === "vertical" ? (
      <VerticalSpine
        birthDate={birthDate}
        model={displayModel}
        onSelect={openEntry}
        referenceDate={referenceDate}
      />
    ) : (
      <StickyYear model={displayModel} onSelect={openEntry} />
    );
  }

  return (
    <PageFrame variant="canvas">
      <PageHeader
        title={<>Timeline</>}
        eyebrow={<>Your life in context</>}
        description={<>See the chapters and moments that shape your life.</>}
        actions={
          <>
            <Button
              variant="primary"
              aria-label="Add moment"
              disabled={tracks.length === 0}
              onClick={() => setSelection({ type: "chooser" })}
              type="button"
            >
              <Icon name="plus" />
              <span>Add moment</span>
            </Button>
          </>
        }
      />
      <div className={styles.summary} aria-label="Timeline summary">
        <Link href="/timeline/tracks">Manage tracks</Link>
        <span aria-hidden="true">·</span>
        <span>{trackCountLabel(tracks.length)}</span>
        <span aria-hidden="true">·</span>
        <span>{entryCountLabel(items.length)}</span>
        {items.some((item) => item.occurredStart) ? (
          <>
            <span aria-hidden="true">·</span>
            <span>{rangeLabel(layout.start, layout.end)}</span>
          </>
        ) : null}
        {birthDateAvailable && !birthDate && !loadError ? (
          <>
            <span aria-hidden="true">·</span>
            <Button
              variant="secondary"
              onClick={() => setShowBirthDatePrompt(true)}
              type="button"
            >
              Set birth date
            </Button>
          </>
        ) : null}
      </div>

      {loadError ? (
        <div className={styles.message} role="alert">
          <Icon name="clock" size={21} />
          <div>
            <strong>Timeline unavailable</strong>
            <p>{loadError}</p>
          </div>
        </div>
      ) : null}

      {!loadError && tracks.length === 0 ? (
        <div className={styles.message}>
          <Icon name="timeline" size={22} />
          <div>
            <strong>Your Timeline needs tracks</strong>
            <p>Open Manage tracks to add a track or show a hidden one.</p>
          </div>
        </div>
      ) : null}

      {!loadError && tracks.length > 0 && timelineStyle !== "classic"
        ? renderAlternativeTimeline()
        : null}

      {!loadError && tracks.length > 0 && timelineStyle === "classic" ? (
        <>
          <section
            className={styles.desktopTimeline}
            aria-label="Timeline by track"
          >
            <div className={styles.timelineHint}>
              <span>Scroll across years</span>
              <small>Select any moment to edit it</small>
            </div>
            {items.some((item) => !item.occurredStart) ? (
              <section
                className={styles.undatedMoments}
                aria-label="Without a calendar date"
              >
                <h2>Without a calendar date</h2>
                <p>
                  These memories stay on their tracks without an invented year.
                </p>
                {tracks
                  .filter((track) =>
                    track.items.some((item) => !item.occurredStart),
                  )
                  .map((track) => (
                    <div key={track.id}>
                      <h3>{track.name}</h3>
                      {track.items
                        .filter((item) => !item.occurredStart)
                        .map((entry) => {
                          const label =
                            entry.title + ", " + timelineEntryDateLabel(entry);
                          return (
                            <button
                              key={entry.id}
                              type="button"
                              onClick={() => openEntry(entry)}
                            >
                              {label}
                            </button>
                          );
                        })}
                    </div>
                  ))}
              </section>
            ) : null}
            <div
              className={styles.timelineViewport}
              data-testid="timeline-viewport"
            >
              <div className={styles.timelineGrid} style={gridStyle}>
                <div className={styles.axisCorner}>Track</div>
                <div className={styles.axis} data-testid="timeline-axis">
                  {layout.yearMarkers.map((marker) => (
                    <span
                      key={marker.year}
                      style={{ left: `${marker.leftPercent}%` }}
                    >
                      {marker.label}
                    </span>
                  ))}
                </div>

                {tracks.map((track) => (
                  <TrackRow
                    key={track.id}
                    layout={layout}
                    onAdd={() => startCreationForTrack(track)}
                    onSelect={openEntry}
                    positions={positions}
                    track={track}
                  />
                ))}
                <div
                  aria-hidden="true"
                  className={styles.todayLine}
                  data-testid="timeline-today"
                />
              </div>
            </div>
          </section>

          <section
            className={styles.mobileTimeline}
            aria-label="Timeline by track"
          >
            {tracks.map((track) => (
              <article className={styles.mobileTrack} key={track.id}>
                <header>
                  <div>
                    <h2>{track.name}</h2>
                    <span>{entryCountLabel(track.items.length)}</span>
                  </div>
                  <button
                    aria-label={`Add a moment to ${track.name}`}
                    onClick={() => startCreationForTrack(track)}
                    type="button"
                  >
                    <Icon name="plus" size={17} />
                  </button>
                </header>
                {track.items.length === 0 ? (
                  <p className={styles.mobileEmpty}>No moments yet.</p>
                ) : (
                  <div className={styles.mobileItems}>
                    {track.items.map((entry) => {
                      const content = (
                        <>
                          <span
                            className={
                              entry.kind === "stage"
                                ? styles.mobileStageMarker
                                : styles.mobileEventMarker
                            }
                          />
                          <span>
                            <strong>{entry.title}</strong>
                            <small>{timelineEntryDateLabel(entry)}</small>
                          </span>
                          <Icon name="chevron" size={15} />
                        </>
                      );

                      return (
                        <button
                          key={entry.id}
                          onClick={() => openEntry(entry)}
                          type="button"
                        >
                          {content}
                        </button>
                      );
                    })}
                  </div>
                )}
              </article>
            ))}
          </section>
        </>
      ) : null}

      {selection?.type === "chooser" ? (
        <MomentTypeChooser
          onClose={closeSelection}
          onSelect={(type) =>
            startCreation(
              type,
              type === "moment" ? (tracks[0]?.id ?? null) : null,
            )
          }
        />
      ) : null}

      {selection?.type === "timeline" ? (
        <TimelineEditor
          collectionOptions={collectionOptions}
          onTrashed={(id) =>
            setConfirmed((current) => {
              const next = new Map(current);
              next.delete(id);
              return next;
            })
          }
          onSaved={(entry) =>
            setConfirmed((values) => new Map(values).set(entry.id, entry))
          }
          entry={selection.entry}
          defaultTimezone={defaultTimezone}
          initialTrackId={selection.initialTrackId}
          key={selection.entry?.id ?? `new:${selection.initialTrackId}`}
          onClose={closeSelection}
          tracks={tracks}
          tagOptions={tagOptions}
        />
      ) : null}

      {selection?.type === "home" ? (
        <HomeEditor
          collectionOptions={collectionOptions}
          defaultTimezone={defaultTimezone}
          home={selection.entry}
          key={selection.entry?.id ?? "new-home-from-timeline"}
          onClose={closeSelection}
          onSaved={() => undefined}
          onTrashed={() => undefined}
          ownerId={ownerId}
          tagOptions={tagOptions}
        />
      ) : null}

      {selection?.type === "vehicle" ? (
        <VehicleEditor
          collectionOptions={collectionOptions}
          defaultTimezone={defaultTimezone}
          key={selection.entry?.id ?? "new-vehicle-from-timeline"}
          onClose={closeSelection}
          onSaved={() => undefined}
          onTrashed={() => undefined}
          ownerId={ownerId}
          tagOptions={tagOptions}
          vehicle={selection.entry}
        />
      ) : null}

      {selection?.type === "first-time" ? (
        <FirstTimeEditor
          collectionOptions={collectionOptions}
          defaultTimezone={defaultTimezone}
          entry={selection.entry}
          key={selection.entry?.id ?? "new-first-time-from-timeline"}
          onClose={closeSelection}
          onSaved={() => undefined}
          ownerId={ownerId}
          tagOptions={tagOptions}
        />
      ) : null}

      {birthDateAvailable && showBirthDatePrompt && !birthDate && !loadError ? (
        <BirthDatePrompt
          maxValue={referenceDate.slice(0, 10)}
          onClose={() => setShowBirthDatePrompt(false)}
          onSaved={(value) => {
            setBirthDate(value);
            setShowBirthDatePrompt(false);
          }}
        />
      ) : null}
    </PageFrame>
  );
}

function EditorLoading() {
  return (
    <div className={styles.dialogBackdrop}>
      <div className={styles.editorLoading} role="status">
        <span />
        <strong>Opening editor</strong>
      </div>
    </div>
  );
}

function TimelineEmptyState({ onAdd }: { onAdd: () => void }) {
  return (
    <div className={styles.message}>
      <Icon name="timeline" size={22} />
      <div>
        <strong>Your Timeline is ready</strong>
        <p>Add a moment or period to begin your story.</p>
        <Button onClick={onAdd} type="button" variant="secondary">
          Add moment
        </Button>
      </div>
    </div>
  );
}

function MomentTypeChooser({
  onClose,
  onSelect,
}: {
  onClose: () => void;
  onSelect: (type: CreationType) => void;
}) {
  const options: {
    description: string;
    icon: "timeline" | "home" | "car" | "star";
    label: string;
    type: CreationType;
  }[] = [
    {
      description: "A flexible event or life stage on any Timeline track.",
      icon: "timeline",
      label: "Moment",
      type: "moment",
    },
    {
      description: "A place you called home, with its facts and memories.",
      icon: "home",
      label: "Home",
      type: "home",
    },
    {
      description: "A car, bike, or other vehicle that carried your story.",
      icon: "car",
      label: "Vehicle",
      type: "vehicle",
    },
    {
      description: "A beginning or milestone you want to remember.",
      icon: "star",
      label: "First Time",
      type: "first-time",
    },
  ];

  return (
    <Dialog
      open
      onOpenChange={(nextOpen) => {
        if (!nextOpen) onClose();
      }}
      title={<>What are you adding?</>}
      titleId="moment-type-heading"
      eyebrow={<>New entry</>}
      closeLabel="Close entry type chooser"
      size="standard"
    >
      <div className={styles.creationOptions}>
        {options.map((option) => (
          <button
            aria-label={`Add ${option.label}`}
            className={styles.creationOption}
            key={option.type}
            onClick={() => onSelect(option.type)}
            type="button"
          >
            <span>
              <Icon name={option.icon} size={21} />
            </span>
            <span>
              <strong>{option.label}</strong>
              <small>{option.description}</small>
            </span>
            <Icon name="chevron" size={16} />
          </button>
        ))}
      </div>
    </Dialog>
  );
}

function BirthDatePrompt({
  maxValue,
  onClose,
  onSaved,
}: {
  maxValue: string;
  onClose: () => void;
  onSaved: (value: string) => void;
}) {
  const router = useRouter();
  const [birthDate, setBirthDate] = useState("");
  const [busy, setBusy] = useState(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!birthDate || busy) return;

    setBusy(true);

    try {
      const result = await saveBirthDate(birthDate);
      if (result.status === "error" || !result.birthDate) {
        notify.error(result.message);
        return;
      }

      onSaved(result.birthDate);
      router.refresh();
      notify.success(result.message);
    } catch {
      notify.error("MemoTrail could not save your birth date. Try again.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <Dialog
      open
      onOpenChange={(nextOpen) => {
        if (!nextOpen) onClose();
      }}
      title={<>When did your story begin?</>}
      titleId="birth-date-heading"
      eyebrow={<>Your starting point</>}
      closeLabel="Close birth date prompt"
      size="compact"
      closeOnInteractOutside={false}
    >
      <form className={styles.birthDateForm} onSubmit={submit}>
        <p>
          Add your birth date so Timeline begins with your life, not just your
          earliest saved moment. It stays private and can be changed in
          Settings.
        </p>
        <DatePickerField
          disabled={busy}
          editable={false}
          granularity="day"
          label="Birth date"
          initialView="year"
          maxValue={maxValue}
          onChange={setBirthDate}
          required
          size="large"
          value={birthDate}
        />
        <div className={styles.birthDateActions}>
          <Button
            variant="secondary"
            disabled={busy}
            onClick={onClose}
            type="button"
          >
            Not now
          </Button>
          <Button variant="primary" disabled={!birthDate || busy} type="submit">
            {busy ? "Saving…" : "Start my Timeline"}
          </Button>
        </div>
      </form>
    </Dialog>
  );
}

function TrackRow({
  layout,
  onAdd,
  onSelect,
  positions,
  track,
}: {
  layout: ReturnType<typeof createTimelineLayout>;
  onAdd: () => void;
  onSelect: (entry: TimelineEntry) => void;
  positions: Map<
    string,
    ReturnType<typeof createTimelineLayout>["positions"][number]
  >;
  track: TimelineTrack;
}) {
  const laneCount = layout.laneCountByTrack[track.id] ?? 1;
  const rowHeight = Math.max(70, laneCount * 49 + 20);

  return (
    <>
      <div className={styles.trackLabel} style={{ height: rowHeight }}>
        <span>
          <strong>{track.name}</strong>
          <small>{track.items.length || "Empty"}</small>
        </span>
        <button
          aria-label={`Add a moment to ${track.name}`}
          onClick={onAdd}
          type="button"
        >
          <Icon name="plus" size={15} />
        </button>
      </div>
      <div className={styles.trackCanvas} style={{ height: rowHeight }}>
        {layout.yearMarkers.map((marker) => (
          <span
            aria-hidden="true"
            className={styles.yearLine}
            key={marker.year}
            style={{ left: `${marker.leftPercent}%` }}
          />
        ))}
        {track.items.map((entry) => {
          const position = positions.get(entry.id);

          if (!position) {
            return null;
          }

          const itemStyle: PositionedStyle = {
            "--item-lane": position.lane,
            "--item-left": `${position.leftPercent}%`,
            "--item-stage-label-offset": `${position.stageLabelOffsetPixels}px`,
            "--item-width": `${position.widthPercent}%`,
          };

          const content = (
            <>
              {entry.kind === "event" ? (
                <span className={styles.eventDot} />
              ) : null}
              <span>{entry.title}</span>
            </>
          );

          const sharedProps = {
            "aria-label": `${entry.title}, ${timelineEntryDateLabel(entry)}`,
            className:
              entry.kind === "stage" ? styles.stageItem : styles.eventItem,
            "data-edge":
              entry.kind === "event" && position.leftPercent > 90
                ? "end"
                : undefined,
            "data-ongoing":
              entry.kind === "stage" && entry.occurredEnd === null
                ? "true"
                : undefined,
            style: itemStyle,
            title: `${entry.title} · ${timelineEntryDateLabel(entry)}`,
          };
          return (
            <button
              {...sharedProps}
              key={entry.id}
              onClick={() => onSelect(entry)}
              type="button"
            >
              {content}
            </button>
          );
        })}
        {track.items.length === 0 ? (
          <button className={styles.emptyTrack} onClick={onAdd} type="button">
            Add the first moment
          </button>
        ) : null}
      </div>
    </>
  );
}

function TimelineEditor({
  collectionOptions,
  defaultTimezone,
  onTrashed,
  onSaved,
  entry,
  initialTrackId,
  onClose,
  tracks,
  tagOptions,
}: {
  collectionOptions: string[];
  defaultTimezone: string;
  onTrashed: (id: string) => void;
  onSaved: (entry: TimelineEntry) => void;
  entry: TimelineEntry | null;
  initialTrackId: string | null;
  onClose: () => void;
  tracks: TimelineTrack[];
  tagOptions: string[];
}) {
  const router = useRouter();
  const requestConfirmation = useConfirmationDialog();
  const titleRef = useRef<HTMLInputElement>(null);
  const initialTimezone = entry?.occurredTimezone ?? defaultTimezone;
  const [body, setBody] = useState(entry?.body ?? "");
  const [collectionInput, setCollectionInput] = useState("");
  const [collectionNames, setCollectionNames] = useState(
    entry?.collectionNames ?? [],
  );
  const originalOccurrence = entry ? entryOccurrence(entry) : undefined;
  const [occurrence, setOccurrence] = useState(() =>
    occurrenceDraft(
      originalOccurrence ?? {
        datePrecision: "unknown",
        occurredAt: null,
        occurredEnd: null,
        occurredLabel: null,
        occurredTimezone: initialTimezone,
      },
    ),
  );
  const [isPending, setIsPending] = useState(false);
  const [kind, setKind] = useState<TimelineKind>(entry?.kind ?? "event");
  const [result, setResult] = useState<TimelineActionResult | null>(null);
  const [tagInput, setTagInput] = useState("");
  const [tagNames, setTagNames] = useState(entry?.tagNames ?? []);
  const [title, setTitle] = useState(entry?.title ?? "");
  const [trackId, setTrackId] = useState(
    entry?.trackId ?? initialTrackId ?? tracks[0]?.id ?? "",
  );

  useEffect(() => {
    titleRef.current?.focus();
  }, []);

  function changeKind(nextKind: TimelineKind) {
    setKind(nextKind);
    if (nextKind === "event")
      setOccurrence((value) => ({
        ...value,
        end: "",
        endMode: "date",
        precision: value.precision === "range" ? "day" : value.precision,
      }));
    setResult(null);
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const resolved = resolveOccurrenceDraft(
      occurrence,
      originalOccurrence,
      kind === "stage",
    );
    if (!resolved.value) {
      setResult({ message: resolved.error, status: "error" });
      return;
    }
    const input: TimelineEntryInput = {
      body,
      collectionNames: namesIncludingDraft(collectionNames, collectionInput),
      datePrecision: resolved.value.datePrecision,
      id: entry?.id ?? null,
      kind,
      occurredEnd: resolved.value.occurredEnd,
      occurredLabel: resolved.value.occurredLabel,
      occurredStart: resolved.value.occurredAt,
      occurredTimezone: resolved.value.occurredTimezone,
      revision: entry?.revision ?? null,
      tagNames: namesIncludingDraft(tagNames, tagInput),
      title,
      trackId,
    };
    const parsed = parseTimelineEntryInput(input);

    if (!parsed.success) {
      setResult({ message: parsed.message, status: "error" });
      return;
    }

    setIsPending(true);
    setResult(null);

    try {
      const nextResult = await saveTimelineEntry(parsed.data);

      if (nextResult.status === "created" || nextResult.status === "saved") {
        if (nextResult.entryId && nextResult.revision)
          onSaved({
            ...parsed.data,
            id: nextResult.entryId,
            revision: nextResult.revision,
            itemKind: "entry",
            itemSubtype: parsed.data.kind === "stage" ? "period" : "moment",
            updatedAt: entry?.updatedAt ?? "",
          });
        router.refresh();
        onClose();
        notify.success(
          nextResult.status === "created" ? "Moment created." : "Moment saved.",
        );
        return;
      }

      setResult(nextResult);
    } catch {
      setResult({
        message: "MemoTrail could not reach the server. Try again when online.",
        status: "error",
      });
    } finally {
      setIsPending(false);
    }
  }

  async function handleTrash() {
    if (!entry) return;
    const confirmed = await requestConfirmation({
      title: <>Move “{entry.title}” to Trash?</>,
      description: <>{"Its history will be preserved."}</>,
      confirmLabel: "Move to Trash",
      eyebrow: <>Recoverable action</>,
      variant: "danger",
    });
    if (!confirmed) return;

    setIsPending(true);
    setResult(null);

    try {
      const nextResult = await trashTimelineEntry({
        id: entry.id,
        revision: entry.revision,
      });

      if (nextResult.status === "trashed") {
        onTrashed(entry.id);
        router.refresh();
        onClose();
        notify.info("Moment moved to Trash.");
        return;
      }

      setResult(nextResult);
    } catch {
      setResult({
        message: "MemoTrail could not reach the server. Try again when online.",
        status: "error",
      });
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
      title={<>{entry ? entry.title : "Add to your story"}</>}
      titleId="timeline-editor-title"
      eyebrow={<>{entry ? "Edit moment" : "New Timeline moment"}</>}
      closeLabel="Close Timeline editor"
      busy={isPending}
      size="wide"
      footer={
        <div className={styles.dialogFooter}>
          <div>
            {entry ? (
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
              form="timeline-workspace-form"
              variant="primary"
              disabled={isPending}
              type="submit"
            >
              {isPending ? "Saving..." : entry ? "Save changes" : "Add moment"}
            </Button>
          </div>
        </div>
      }
    >
      {" "}
      <form
        className={styles.editorForm}
        id="timeline-workspace-form"
        onSubmit={handleSubmit}
      >
        <fieldset className={styles.kindPicker}>
          <legend>Timeline shape</legend>
          <div>
            <button
              aria-pressed={kind === "stage"}
              className={kind === "stage" ? styles.kindActive : undefined}
              onClick={() => changeKind("stage")}
              type="button"
            >
              <Icon name="timeline" size={17} />
              Period
            </button>
            <button
              aria-pressed={kind === "event"}
              className={kind === "event" ? styles.kindActive : undefined}
              onClick={() => changeKind("event")}
              type="button"
            >
              <Icon name="star" size={17} />
              Moment
            </button>
          </div>
          <p>
            {kind === "stage"
              ? "A meaningful period that spans time and may still be ongoing."
              : "A meaningful moment on one date."}
          </p>
        </fieldset>

        <div className={styles.formGrid}>
          <label className={styles.fullField}>
            <span>
              Title
              <span aria-hidden="true" className={styles.requiredMark}>
                *
              </span>
            </span>
            <input
              aria-label="Title"
              maxLength={timelineTitleLimit}
              onChange={(event) => setTitle(event.target.value)}
              placeholder={
                kind === "stage" ? "Living in Philadelphia" : "First ski day"
              }
              ref={titleRef}
              required
              value={title}
            />
          </label>

          <label className={styles.fullField}>
            <span>
              Track
              <span aria-hidden="true" className={styles.requiredMark}>
                *
              </span>
            </span>
            <select
              aria-label="Track"
              onChange={(event) => setTrackId(event.target.value)}
              required
              value={trackId}
            >
              {tracks.map((track) => (
                <option key={track.id} value={track.id}>
                  {track.name}
                </option>
              ))}
            </select>
          </label>

          <div className={styles.fullField}>
            <OccurrenceEditor
              defaultTimezone={defaultTimezone}
              value={occurrence}
              onChange={setOccurrence}
              disabled={isPending}
              span={kind === "stage"}
              point={kind === "event"}
            />
          </div>

          <label className={styles.fullField}>
            <span>Notes</span>
            <textarea
              aria-label="Notes"
              maxLength={timelineBodyLimit}
              onChange={(event) => setBody(event.target.value)}
              placeholder="What made this period or moment meaningful?"
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
        </div>

        {result ? (
          <p className={styles.formMessage} role="alert">
            {result.message}
          </p>
        ) : null}
      </form>
    </Dialog>
  );
}

function entryOccurrence(entry: TimelineEntry): Occurrence {
  return {
    datePrecision: entry.datePrecision,
    occurredAt: entry.occurredStart,
    occurredEnd: entry.occurredEnd,
    occurredLabel: entry.occurredLabel,
    occurredTimezone: entry.occurredTimezone,
  };
}

function namesIncludingDraft(names: string[], draft: string) {
  const name = draft.trim();
  return name ? [...names, name] : names;
}
function rangeLabel(start: string, end: string) {
  return `${new Date(start).getUTCFullYear()} to ${new Date(end).getUTCFullYear()}`;
}

function trackCountLabel(count: number) {
  return `${count} ${count === 1 ? "track" : "tracks"}`;
}

function entryCountLabel(count: number) {
  return `${count} ${count === 1 ? "moment" : "moments"}`;
}
