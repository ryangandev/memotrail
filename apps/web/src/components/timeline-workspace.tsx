"use client";
import { Dialog } from "@/components/dialog";
import { PageHeader } from "@/components/page-header";
import { Button } from "@/components/button";
import { notify } from "@/components/app-toast";

import Link from "next/link";
import dynamic from "next/dynamic";
import {
  useEffect,
  useMemo,
  useRef,
  useState,
  type CSSProperties,
  type FormEvent,
  type RefObject,
} from "react";
import { useRouter } from "next/navigation";
import { saveBirthDate } from "@/app/settings/actions";
import { Icon } from "@/components/icon";
import { DatePickerField } from "@/components/date-picker-field";
import { PageFrame } from "@/components/page-frame";
import { SeparatedList } from "@/components/separated-list";
import type { EntryMarks } from "@/components/entry-marks-fields";
import type { TimelineItem } from "@/lib/data/timeline";
import {
  createTimelineLayout,
  estimateLabelWidth,
  type TimelineBand,
  type TimelineLayoutSource,
} from "@/lib/data/timeline-layout";
import {
  timelineItemAccessibleName,
  timelineItemDateLabel,
  timelineItemDurationLabel,
  timelineUndatedLabel,
} from "@/lib/data/timeline-presentation";
import { wikiEntryHref } from "@/lib/data/wiki-item";
import styles from "@/components/timeline-workspace.module.css";

const NewEntryDialog = dynamic(
  () =>
    import("@/components/entry-editor-dialog").then(
      (module) => module.NewEntryDialog,
    ),
  { loading: () => <EditorLoading /> },
);

type EditorSelection = { type: "chooser" } | { type: "new"; marks: EntryMarks };

type CreationType = "chapter" | "first-time";

// A Chapter that is also a First Time draws a star before its title, which the title's
// measured width does not include.
const starAllowancePixels = 18;

type PositionedStyle = CSSProperties & {
  "--item-bar-width": string;
  "--item-label-width": string;
  "--item-left": string;
  "--item-offset": string;
  "--item-row": number;
  "--item-width": string;
};

type GridStyle = CSSProperties & {
  "--timeline-canvas-width": string;
  "--timeline-today-percent": number;
};

export function TimelineWorkspace({
  birthDate: serverBirthDate,
  birthDateAvailable,
  chapters,
  defaultTimezone,
  firstTimes,
  loadError,
  ownerId,
  referenceDate,
  tagOptions,
}: {
  birthDate: string | null;
  birthDateAvailable: boolean;
  chapters: TimelineItem[];
  defaultTimezone: string;
  firstTimes: TimelineItem[];
  loadError: string | null;
  ownerId: string;
  referenceDate: string;
  tagOptions: string[];
}) {
  const [selection, setSelection] = useState<EditorSelection | null>(null);
  const [birthDate, setBirthDate] = useState(serverBirthDate);
  const [showBirthDatePrompt, setShowBirthDatePrompt] = useState(false);
  const items = useMemo(() => [...chapters, ...firstTimes], [chapters, firstTimes]);
  const labelProbe = useRef<HTMLSpanElement>(null);
  const measureLabel = useLabelMeasure(labelProbe);
  const viewport = useRef<HTMLDivElement>(null);
  const fillWidth = useCanvasFillWidth(viewport);
  const layout = useMemo(
    () =>
      createTimelineLayout(
        items.flatMap((item): TimelineLayoutSource[] =>
          item.windowStart
            ? [
                {
                  band: item.isChapter ? "chapters" : "first-times",
                  id: item.id,
                  labelWidthPixels:
                    measureLabel(item.title) +
                    (item.isChapter && item.isFirstTime
                      ? starAllowancePixels
                      : 0),
                  shape: item.isChapter ? "bar" : "point",
                  windowEnd: item.windowEnd,
                  windowStart: item.windowStart,
                },
              ]
            : [],
        ),
        new Date(referenceDate),
        birthDate,
        fillWidth,
      ),
    [birthDate, fillWidth, items, measureLabel, referenceDate],
  );
  const positions = useMemo(
    () => new Map(layout.positions.map((position) => [position.id, position])),
    [layout.positions],
  );
  const bands: { band: TimelineBand; label: string; members: TimelineItem[] }[] = [
    { band: "chapters", label: "Chapters", members: chapters },
    { band: "first-times", label: "First Times", members: firstTimes },
  ];
  const gridStyle: GridStyle = {
    "--timeline-canvas-width": `${layout.canvasWidth}px`,
    "--timeline-today-percent": layout.todayPercent,
  };
  const now = useMemo(() => new Date(referenceDate), [referenceDate]);
  const firstTimeCount =
    firstTimes.length + chapters.filter((item) => item.isFirstTime).length;
  const undated = items.filter((item) => !item.windowStart);

  function startCreation(type: CreationType) {
    setSelection({
      type: "new",
      marks: {
        isChapter: type === "chapter",
        isFirstTime: type === "first-time",
      },
    });
  }

  function closeSelection() {
    setSelection(null);
  }

  return (
    <PageFrame variant="canvas">
      <PageHeader
        title={<>Timeline</>}
        eyebrow={<>Your life in context</>}
        description={<>See the Chapters of your life and your First Times.</>}
        actions={
          <Button
            variant="primary"
            onClick={() => setSelection({ type: "chooser" })}
            type="button"
          >
            <Icon name="plus" />
            <span>Add to Timeline</span>
          </Button>
        }
      />
      <div className={styles.summary} aria-label="Timeline summary">
        <SeparatedList>
          <span>{countLabel(chapters.length, "Chapter")}</span>
          <span>{countLabel(firstTimeCount, "First Time")}</span>
          {items.some((item) => item.windowStart) ? (
            <span>{rangeLabel(layout.start, layout.end)}</span>
          ) : null}
        </SeparatedList>
        {/* Its border sets the button apart, so it needs no separator. */}
        {birthDateAvailable && !birthDate && !loadError ? (
          <Button
            variant="secondary"
            onClick={() => setShowBirthDatePrompt(true)}
            type="button"
          >
            Set birth date
          </Button>
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

      {!loadError ? (
        <>
          <section
            className={styles.desktopTimeline}
            aria-label="Timeline by year"
          >
            <div className={styles.timelineHint}>
              <span>Scroll across years</span>
              <small>Select anything to open it</small>
            </div>
            <div
              className={styles.timelineViewport}
              data-testid="timeline-viewport"
              ref={viewport}
            >
              <div className={styles.timelineGrid} style={gridStyle}>
                <div className={styles.axis} data-testid="timeline-axis">
                  {layout.yearMarkers.map((marker) => (
                    <span
                      data-edge={
                        marker.leftPercent === 0
                          ? "start"
                          : marker.leftPercent === 100
                            ? "end"
                            : undefined
                      }
                      key={marker.year}
                      style={{ left: `${marker.leftPercent}%` }}
                    >
                      {marker.label}
                    </span>
                  ))}
                </div>

                {items.length === 0 ? (
                  <div className={styles.band}>
                    <button
                      className={styles.emptyTimeline}
                      onClick={() => setSelection({ type: "chooser" })}
                      type="button"
                    >
                      {emptyLabel}
                    </button>
                  </div>
                ) : null}
                {bands.map(({ band, label, members }) =>
                  members.length > 0 ? (
                    <BandRow
                      band={band}
                      items={members}
                      key={band}
                      label={label}
                      layout={layout}
                      positions={positions}
                    />
                  ) : null,
                )}
                <div
                  aria-hidden="true"
                  className={styles.todayLine}
                  data-testid="timeline-today"
                />
                <span
                  aria-hidden="true"
                  className={styles.labelProbe}
                  ref={labelProbe}
                />
              </div>
            </div>
            {undated.length > 0 ? (
              <section
                className={styles.undatedItems}
                aria-label="Without a calendar date"
              >
                <h2>Without a calendar date</h2>
                <p>
                  These have no calendar date, so they are not placed on the
                  years above.
                </p>
                <div>
                  {undated.map((item) => (
                    <Link href={wikiEntryHref(item)} key={item.id}>
                      {item.title}, {timelineUndatedLabel(item)}
                    </Link>
                  ))}
                </div>
              </section>
            ) : null}
          </section>

          <section
            className={styles.mobileTimeline}
            aria-label="Timeline list"
          >
            {items.length === 0 ? (
              <p className={styles.mobileEmpty}>{emptyLabel}</p>
            ) : null}
            {bands.map(({ band, label, members }) =>
              members.length > 0 ? (
                <article className={styles.mobileBand} key={band}>
                  <header>
                    <h2>{label}</h2>
                    <span>{members.length}</span>
                  </header>
                  <div aria-label={label} className={styles.mobileItems} role="list">
                    {members.map((item) => {
                      const duration = timelineItemDurationLabel(item, now);
                      return (
                        <Link
                          href={wikiEntryHref(item)}
                          key={item.id}
                          role="listitem"
                        >
                          <span
                            className={
                              item.isChapter
                                ? styles.mobileBarMarker
                                : styles.mobilePointMarker
                            }
                          />
                          <span>
                            <strong>{item.title}</strong>
                            <small>
                              {item.windowStart
                                ? timelineItemDateLabel(item)
                                : timelineUndatedLabel(item)}
                              {duration ? ` · ${duration}` : ""}
                            </small>
                          </span>
                          <Icon name="chevron" size={15} />
                        </Link>
                      );
                    })}
                  </div>
                </article>
              ) : null,
            )}
          </section>
        </>
      ) : null}

      {selection?.type === "chooser" ? (
        <TimelineTypeChooser
          onClose={closeSelection}
          onSelect={(type) => startCreation(type)}
        />
      ) : null}

      {selection?.type === "new" ? (
        <NewEntryDialog
          marks={selection.marks}
          onClose={closeSelection}
          ownerId={ownerId}
          tagOptions={tagOptions}
          timezone={defaultTimezone}
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

function TimelineTypeChooser({
  onClose,
  onSelect,
}: {
  onClose: () => void;
  onSelect: (type: CreationType) => void;
}) {
  const options: {
    description: string;
    icon: "timeline" | "star";
    label: string;
    type: CreationType;
  }[] = [
    {
      description:
        "A stretch of your life, like a home, a job, or a school year.",
      icon: "timeline",
      label: "Chapter",
      type: "chapter",
    },
    {
      description: "The first time you did something.",
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
      titleId="timeline-type-heading"
      eyebrow={<>Add to Timeline</>}
      closeLabel="Close Timeline chooser"
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
            Cancel
          </Button>
          <Button variant="primary" disabled={!birthDate || busy} type="submit">
            {busy ? "Saving…" : "Save birth date"}
          </Button>
        </div>
      </form>
    </Dialog>
  );
}

function BandRow({
  band,
  items,
  label,
  layout,
  positions,
}: {
  band: TimelineBand;
  items: TimelineItem[];
  label: string;
  layout: ReturnType<typeof createTimelineLayout>;
  positions: Map<
    string,
    ReturnType<typeof createTimelineLayout>["positions"][number]
  >;
}) {
  const rowCount = layout.rowCountByBand[band] ?? 1;
  const rowHeight = Math.max(70, rowCount * 49 + 20);

  return (
    <ul
      aria-label={label}
      className={styles.band}
      data-testid="timeline-band"
      style={{ height: rowHeight }}
    >
      {layout.yearMarkers.map((marker) => (
        <li
          aria-hidden="true"
          className={styles.yearLine}
          key={marker.year}
          style={{ left: `${marker.leftPercent}%` }}
        />
      ))}
      {items.map((item) => {
        const position = positions.get(item.id);

        if (!position) {
          return null;
        }

        const itemStyle: PositionedStyle = {
          "--item-bar-width": `${position.barWidthPixels}px`,
          "--item-label-width": `${position.labelWidthPixels}px`,
          "--item-left": `${position.leftPercent}%`,
          "--item-offset": `${position.offsetPixels}px`,
          "--item-row": position.row,
          "--item-width": `${position.widthPixels}px`,
        };
        const dateLabel = timelineItemDateLabel(item);

        return (
          <li
            className={item.isChapter ? styles.barItem : styles.pointItem}
            data-label={position.labelPlacement}
            data-ongoing={
              item.isChapter && item.windowEnd === null ? "true" : undefined
            }
            key={item.id}
            style={itemStyle}
          >
            <Link
              aria-label={timelineItemAccessibleName(item)}
              href={wikiEntryHref(item)}
              title={`${item.title} · ${dateLabel}`}
            >
              {!item.isChapter ? (
                <span className={styles.pointDot} />
              ) : position.labelPlacement === "inside" ? null : (
                <span className={styles.bar} />
              )}
              <span className={styles.itemTitle}>
                {item.isChapter && item.isFirstTime ? (
                  <span className={styles.firstTimeStar}>
                    <Icon name="star" size={12} />
                  </span>
                ) : null}
                {item.title}
              </span>
            </Link>
          </li>
        );
      })}
    </ul>
  );
}

// Measures titles in the band item font once it has loaded, so the layout knows which
// fit inside their bar. The server and first render estimate, which keeps hydration
// stable.
function useLabelMeasure(probe: RefObject<HTMLSpanElement | null>) {
  const [measure, setMeasure] = useState<(text: string) => number>(
    () => estimateLabelWidth,
  );

  useEffect(() => {
    let active = true;

    void document.fonts.ready.then(() => {
      const element = probe.current;
      const context = document.createElement("canvas").getContext("2d");
      if (!active || !element || !context) return;
      const style = getComputedStyle(element);
      context.font = `${style.fontStyle} ${style.fontWeight} ${style.fontSize} ${style.fontFamily}`;
      const widths = new Map<string, number>();
      setMeasure(() => (text: string) => {
        let width = widths.get(text);
        if (width === undefined) {
          width = Math.ceil(context.measureText(text).width);
          widths.set(text, width);
        }
        return width;
      });
    });

    return () => {
      active = false;
    };
  }, [probe]);

  return measure;
}

// Tracks the viewport width, so an empty or short Timeline fills its card. The server and
// first render use the minimum canvas, which keeps hydration stable.
function useCanvasFillWidth(viewport: RefObject<HTMLDivElement | null>) {
  const [width, setWidth] = useState(0);

  useEffect(() => {
    const element = viewport.current;
    if (!element) return;
    const observer = new ResizeObserver(() =>
      setWidth(element.getBoundingClientRect().width),
    );
    observer.observe(element);
    return () => observer.disconnect();
  }, [viewport]);

  return width;
}

const emptyLabel = "Add a Chapter or a First Time to start your Timeline.";

function rangeLabel(start: string, end: string) {
  return `${new Date(start).getUTCFullYear()} to ${new Date(end).getUTCFullYear()}`;
}

function countLabel(count: number, noun: string) {
  return `${count} ${noun}${count === 1 ? "" : "s"}`;
}
