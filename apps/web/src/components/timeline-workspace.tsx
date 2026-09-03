"use client";

import Link from "next/link";
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
import { Icon } from "@/components/icon";
import type { TimelineEntry, TimelineTrack } from "@/lib/data/timeline";
import {
  localDateToISOString,
  localDateValue,
  parseTimelineEntryInput,
  timelineBodyLimit,
  timelineLabelLimit,
  timelineTitleLimit,
  type TimelineDatePrecision,
  type TimelineEntryInput,
  type TimelineKind,
} from "@/lib/data/timeline-input";
import { createTimelineLayout } from "@/lib/data/timeline-layout";
import styles from "@/app/timeline/page.module.css";

type EditorSelection =
  | { entry: TimelineEntry; initialTrackId: null }
  | { entry: null; initialTrackId: string | null };

type PositionedStyle = CSSProperties & {
  "--item-lane": number;
  "--item-left": string;
  "--item-width": string;
};

type GridStyle = CSSProperties & {
  "--timeline-canvas-width": string;
};

const precisionOptions: { label: string; value: TimelineDatePrecision }[] = [
  { label: "Exact day", value: "day" },
  { label: "Month", value: "month" },
  { label: "Year", value: "year" },
  { label: "Approximate", value: "approximate" },
  { label: "Age-based", value: "age" },
  { label: "Date range", value: "range" },
  { label: "Unknown", value: "unknown" },
];

export function TimelineWorkspace({
  loadError,
  referenceDate,
  tracks,
}: {
  loadError: string | null;
  referenceDate: string;
  tracks: TimelineTrack[];
}) {
  const [selection, setSelection] = useState<EditorSelection | null>(null);
  const items = useMemo(() => tracks.flatMap((track) => track.items), [tracks]);
  const layout = useMemo(
    () => createTimelineLayout(items, new Date(referenceDate)),
    [items, referenceDate],
  );
  const positions = useMemo(
    () => new Map(layout.positions.map((position) => [position.id, position])),
    [layout.positions],
  );
  const canvasWidth = Math.max(840, layout.yearMarkers.length * 112);
  const gridStyle: GridStyle = {
    "--timeline-canvas-width": `${canvasWidth}px`,
  };

  return (
    <div className={styles.content}>
      <header className={styles.pageHeader}>
        <div>
          <p className={styles.eyebrow}>Your life in context</p>
          <h1>Timeline</h1>
          <p>See the chapters, places, and moments that overlap your story.</p>
        </div>
        <button
          className={styles.addButton}
          disabled={tracks.length === 0}
          onClick={() =>
            setSelection({ entry: null, initialTrackId: tracks[0]?.id ?? null })
          }
          type="button"
        >
          <Icon name="plus" />
          <span>Add moment</span>
        </button>
      </header>

      <div className={styles.summary} aria-label="Timeline summary">
        <span>{trackCountLabel(tracks.length)}</span>
        <span aria-hidden="true">·</span>
        <span>{entryCountLabel(items.length)}</span>
        {items.length > 0 ? (
          <>
            <span aria-hidden="true">·</span>
            <span>{rangeLabel(layout.start, layout.end)}</span>
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
            <p>Refresh after your default Timeline tracks are available.</p>
          </div>
        </div>
      ) : null}

      {!loadError && tracks.length > 0 ? (
        <>
          <section
            className={styles.desktopTimeline}
            aria-label="Timeline by track"
          >
            <div className={styles.timelineHint}>
              <span>Scroll across years</span>
              <small>Select any moment to edit it</small>
            </div>
            <div className={styles.timelineViewport}>
              <div className={styles.timelineGrid} style={gridStyle}>
                <div className={styles.axisCorner}>Track</div>
                <div className={styles.axis}>
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
                    onAdd={() =>
                      setSelection({ entry: null, initialTrackId: track.id })
                    }
                    onSelect={(entry) =>
                      setSelection({ entry, initialTrackId: null })
                    }
                    positions={positions}
                    track={track}
                  />
                ))}
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
                    onClick={() =>
                      setSelection({ entry: null, initialTrackId: track.id })
                    }
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
                            <small>{entryDateLabel(entry)}</small>
                          </span>
                          <Icon name="chevron" size={15} />
                        </>
                      );

                      return entry.entryType === "home" ? (
                        <Link href={`/homes?entry=${entry.id}`} key={entry.id}>
                          {content}
                        </Link>
                      ) : (
                        <button
                          key={entry.id}
                          onClick={() =>
                            setSelection({ entry, initialTrackId: null })
                          }
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

      {selection ? (
        <TimelineEditor
          entry={selection.entry}
          initialTrackId={selection.initialTrackId}
          key={selection.entry?.id ?? `new:${selection.initialTrackId}`}
          onClose={() => setSelection(null)}
          tracks={tracks}
        />
      ) : null}
    </div>
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
            "aria-label": `${entry.title}, ${entryDateLabel(entry)}`,
            className:
              entry.kind === "stage" ? styles.stageItem : styles.eventItem,
            style: itemStyle,
            title: `${entry.title} · ${entryDateLabel(entry)}`,
          };

          return entry.entryType === "home" ? (
            <Link
              {...sharedProps}
              href={`/homes?entry=${entry.id}`}
              key={entry.id}
            >
              {content}
            </Link>
          ) : (
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
  entry,
  initialTrackId,
  onClose,
  tracks,
}: {
  entry: TimelineEntry | null;
  initialTrackId: string | null;
  onClose: () => void;
  tracks: TimelineTrack[];
}) {
  const router = useRouter();
  const titleRef = useRef<HTMLInputElement>(null);
  const initialTimezone = entry?.occurredTimezone ?? localTimezone();
  const [body, setBody] = useState(entry?.body ?? "");
  const [datePrecision, setDatePrecision] = useState<TimelineDatePrecision>(
    entry?.datePrecision ?? "range",
  );
  const [endDate, setEndDate] = useState(
    entry?.occurredEnd
      ? localDateValue(entry.occurredEnd, initialTimezone)
      : "",
  );
  const [isPending, setIsPending] = useState(false);
  const [kind, setKind] = useState<TimelineKind>(entry?.kind ?? "stage");
  const [occurredLabel, setOccurredLabel] = useState(
    entry?.occurredLabel ?? "",
  );
  const [occurredTimezone] = useState(initialTimezone);
  const [result, setResult] = useState<TimelineActionResult | null>(null);
  const [startDate, setStartDate] = useState(
    entry
      ? localDateValue(entry.occurredStart, initialTimezone)
      : localDateValue(new Date().toISOString(), initialTimezone),
  );
  const [title, setTitle] = useState(entry?.title ?? "");
  const [trackId, setTrackId] = useState(
    entry?.trackId ?? initialTrackId ?? tracks[0]?.id ?? "",
  );

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

  function changeKind(nextKind: TimelineKind) {
    setKind(nextKind);
    setEndDate("");
    setDatePrecision(nextKind === "stage" ? "range" : "day");
    setResult(null);
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const occurredStart = localDateToISOString(startDate, occurredTimezone);
    const occurredEnd =
      kind === "stage" && endDate
        ? localDateToISOString(endDate, occurredTimezone)
        : null;
    const input: TimelineEntryInput = {
      body,
      datePrecision,
      id: entry?.id ?? null,
      kind,
      occurredEnd,
      occurredLabel: occurredLabel || null,
      occurredStart: occurredStart ?? startDate,
      occurredTimezone,
      revision: entry?.revision ?? null,
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
        router.refresh();
        onClose();
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
    if (
      !entry ||
      !window.confirm(
        `Move “${entry.title}” to Trash? Its history will be preserved.`,
      )
    ) {
      return;
    }

    setIsPending(true);
    setResult(null);

    try {
      const nextResult = await trashTimelineEntry({
        id: entry.id,
        revision: entry.revision,
      });

      if (nextResult.status === "trashed") {
        router.refresh();
        onClose();
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
    <div
      aria-labelledby="timeline-editor-title"
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
            <p>{entry ? "Edit moment" : "New Timeline moment"}</p>
            <h2 id="timeline-editor-title">
              {entry ? entry.title : "Add to your story"}
            </h2>
          </div>
          <button
            aria-label="Close Timeline editor"
            disabled={isPending}
            onClick={onClose}
            type="button"
          >
            ×
          </button>
        </header>

        <form onSubmit={handleSubmit}>
          <fieldset className={styles.kindPicker}>
            <legend>Moment type</legend>
            <div>
              <button
                aria-pressed={kind === "stage"}
                className={kind === "stage" ? styles.kindActive : undefined}
                onClick={() => changeKind("stage")}
                type="button"
              >
                <Icon name="timeline" size={17} />
                Stage
              </button>
              <button
                aria-pressed={kind === "event"}
                className={kind === "event" ? styles.kindActive : undefined}
                onClick={() => changeKind("event")}
                type="button"
              >
                <Icon name="star" size={17} />
                Event
              </button>
            </div>
            <p>
              {kind === "stage"
                ? "A chapter that spans time and may still be ongoing."
                : "A meaningful moment on one date."}
            </p>
          </fieldset>

          <div className={styles.formGrid}>
            <label className={styles.fullField}>
              <span>Title</span>
              <input
                maxLength={timelineTitleLimit}
                onChange={(event) => setTitle(event.target.value)}
                placeholder={
                  kind === "stage" ? "Living in Philadelphia" : "First ski day"
                }
                ref={titleRef}
                value={title}
              />
            </label>

            <label>
              <span>Track</span>
              <select
                onChange={(event) => setTrackId(event.target.value)}
                value={trackId}
              >
                {tracks.map((track) => (
                  <option key={track.id} value={track.id}>
                    {track.name}
                  </option>
                ))}
              </select>
            </label>

            <label>
              <span>Date precision</span>
              <select
                onChange={(event) =>
                  setDatePrecision(event.target.value as TimelineDatePrecision)
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

            <label>
              <span>{kind === "stage" ? "Start date" : "Date"}</span>
              <input
                onChange={(event) => setStartDate(event.target.value)}
                required
                type="date"
                value={startDate}
              />
            </label>

            {kind === "stage" ? (
              <label>
                <span>
                  End date <small>Optional</small>
                </span>
                <input
                  min={startDate}
                  onChange={(event) => setEndDate(event.target.value)}
                  type="date"
                  value={endDate}
                />
              </label>
            ) : (
              <div className={styles.presentNote}>
                <Icon name="calendar" size={17} />
                Events appear as a point in time.
              </div>
            )}

            <label className={styles.fullField}>
              <span>
                Human date label <small>Optional</small>
              </span>
              <input
                maxLength={timelineLabelLimit}
                onChange={(event) => setOccurredLabel(event.target.value)}
                placeholder="For example: Ages 12 to 25"
                value={occurredLabel}
              />
              <small>Shown instead of the formatted date when provided.</small>
            </label>

            <label className={styles.fullField}>
              <span>
                Notes <small>Optional</small>
              </span>
              <textarea
                maxLength={timelineBodyLimit}
                onChange={(event) => setBody(event.target.value)}
                placeholder="What made this chapter or moment meaningful?"
                rows={5}
                value={body}
              />
            </label>
          </div>

          {result ? (
            <p className={styles.formMessage} role="alert">
              {result.message}
            </p>
          ) : null}

          <footer className={styles.dialogFooter}>
            <div>
              {entry ? (
                <button
                  className={styles.trashButton}
                  disabled={isPending}
                  onClick={() => void handleTrash()}
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
                  : entry
                    ? "Save changes"
                    : "Add moment"}
              </button>
            </div>
          </footer>
        </form>
      </div>
    </div>
  );
}

function entryDateLabel(entry: TimelineEntry) {
  if (entry.occurredLabel) {
    return entry.occurredLabel;
  }

  const start = formatTimelineDate(
    entry.occurredStart,
    entry.datePrecision,
    entry.occurredTimezone,
  );

  if (entry.kind === "event") {
    return start;
  }

  const end = entry.occurredEnd
    ? formatTimelineDate(
        entry.occurredEnd,
        entry.datePrecision,
        entry.occurredTimezone,
      )
    : "Present";
  return `${start} - ${end}`;
}

function formatTimelineDate(
  value: string,
  precision: TimelineDatePrecision,
  timeZone: string,
) {
  const date = new Date(value);
  const options: Intl.DateTimeFormatOptions =
    precision === "year"
      ? { year: "numeric" }
      : precision === "month"
        ? { month: "short", year: "numeric" }
        : { day: "numeric", month: "short", year: "numeric" };

  try {
    return new Intl.DateTimeFormat("en-US", { ...options, timeZone }).format(
      date,
    );
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

function rangeLabel(start: string, end: string) {
  return `${new Date(start).getUTCFullYear()} to ${new Date(end).getUTCFullYear()}`;
}

function trackCountLabel(count: number) {
  return `${count} ${count === 1 ? "track" : "tracks"}`;
}

function entryCountLabel(count: number) {
  return `${count} ${count === 1 ? "moment" : "moments"}`;
}
