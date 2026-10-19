"use client";
import { Dialog } from "@/components/dialog";
import { PageHeader } from "@/components/page-header";
import { Button } from "@/components/button";
import { notify } from "@/components/app-toast";

import Link from "next/link";
import dynamic from "next/dynamic";
import {
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
  type CSSProperties,
  type FormEvent,
  type RefObject,
} from "react";
import { useRouter } from "next/navigation";
import { saveBirthDate } from "@/app/settings/actions";
import { EmptyState } from "@/components/empty-state";
import { Icon } from "@/components/icon";
import { DatePickerField } from "@/components/date-picker-field";
import { PageFrame } from "@/components/page-frame";
import { SegmentedControl } from "@/components/segmented-control";
import { SeparatedList } from "@/components/separated-list";
import { ChapterSuggestionCard } from "@/components/chapter-suggestion-card";
import type { EntryMarks } from "@/components/entry-marks-fields";
import type { ChapterSuggestion } from "@/lib/data/review-input";
import type { TimelineItem } from "@/lib/data/timeline";
import {
  createTimelineLayout,
  estimateLabelWidth,
  type TimelineBand,
  type TimelineLayout,
  type TimelineLayoutSource,
  type TimelineZoom,
} from "@/lib/data/timeline-layout";
import {
  timelineItemAccessibleName,
  timelineItemDateLabel,
  timelineRowDateLabel,
  timelineToday,
  timelineYearGroups,
  type TimelineYearGroup,
} from "@/lib/data/timeline-presentation";
import { wikiEntryHref } from "@/lib/data/wiki-item";
import { countLabel } from "@/lib/count-label";
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

// Where today sits across the visible width when Timeline opens and when Today is pressed: in
// the right third, with the months ahead still in view.
const todayAnchor = 0.72;

const zoomOptions = [
  { label: "Years", value: "years" },
  { label: "Months", value: "months" },
] as const;

// Where to scroll once the next layout is drawn: today at its anchor, or the date that was
// under a given fraction of the view before the zoom changed.
type ScrollTarget =
  { type: "today" } | { fraction: number; time: number; type: "date" };

type PositionedStyle = CSSProperties & {
  "--item-bar-width": string;
  "--item-label-width": string;
  "--item-left": string;
  "--item-offset": string;
  "--item-row": number;
  "--item-width": string;
};

type CanvasStyle = CSSProperties & {
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
  suggestion,
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
  /** The oldest Chapter suggestion still waiting, or null. */
  suggestion: ChapterSuggestion | null;
  tagOptions: string[];
}) {
  const [selection, setSelection] = useState<EditorSelection | null>(null);
  const [birthDate, setBirthDate] = useState(serverBirthDate);
  const [showBirthDatePrompt, setShowBirthDatePrompt] = useState(false);
  const [zoom, setZoom] = useState<TimelineZoom>("months");
  const items = useMemo(
    () => [...chapters, ...firstTimes],
    [chapters, firstTimes],
  );
  const barProbe = useRef<HTMLSpanElement>(null);
  const pointProbe = useRef<HTMLSpanElement>(null);
  const measureBarLabel = useLabelMeasure(barProbe);
  const measurePointLabel = useLabelMeasure(pointProbe);
  const viewport = useRef<HTMLDivElement>(null);
  const todayRule = useRef<HTMLLIElement>(null);
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
                  labelWidthPixels: item.isChapter
                    ? measureBarLabel(item.title) +
                      (item.isFirstTime ? starAllowancePixels : 0)
                    : measurePointLabel(item.title),
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
        zoom,
      ),
    [
      birthDate,
      fillWidth,
      items,
      measureBarLabel,
      measurePointLabel,
      referenceDate,
      zoom,
    ],
  );
  // The first measured layout opens at today.
  const scrollTarget = useRef<ScrollTarget | null>({ type: "today" });
  const canvas = useRef<HTMLDivElement>(null);

  // Scrolls once a layout is drawn at the measured width: on opening, today in the right
  // third, and after a zoom, the date that was in view back where it was. Until the first
  // scroll the canvas is transparent, so the board never flashes the start of life.
  useLayoutEffect(() => {
    const element = viewport.current;
    const target = scrollTarget.current;
    if (!element || !canvas.current || fillWidth === 0 || !target) return;

    scrollTarget.current = null;
    element.scrollLeft = targetScrollLeft(target, layout, element.clientWidth);
    canvas.current.dataset.positioned = "true";
  }, [fillWidth, layout]);
  const positions = useMemo(
    () => new Map(layout.positions.map((position) => [position.id, position])),
    [layout.positions],
  );
  const shownBands = (
    [
      { band: "chapters", label: "Chapters", members: chapters },
      { band: "first-times", label: "First Times", members: firstTimes },
    ] satisfies {
      band: TimelineBand;
      label: string;
      members: TimelineItem[];
    }[]
  ).filter(({ members }) => members.length > 0);
  const ticks = useMemo(
    () =>
      [
        ...layout.yearMarkers.map((marker) => ({
          key: `year-${marker.year}`,
          kind: "year" as const,
          label: marker.label,
          leftPercent: marker.leftPercent,
        })),
        ...layout.monthMarkers.map((marker) => ({
          key: `month-${marker.year}-${marker.month}`,
          kind: "month" as const,
          label: marker.label,
          leftPercent: marker.leftPercent,
        })),
      ].sort((a, b) => a.leftPercent - b.leftPercent),
    [layout.monthMarkers, layout.yearMarkers],
  );
  const canvasStyle: CanvasStyle = {
    "--timeline-canvas-width": `${layout.canvasWidth}px`,
    "--timeline-today-percent": layout.todayPercent,
  };
  // Close to the end of the Timeline, the Today label sits before its line.
  const todayX = (layout.todayPercent / 100) * layout.canvasWidth;
  const todayLabelBefore = layout.canvasWidth - todayX < 64;
  // A tick label that would print under the Today label keeps its line but not its text.
  const todayLabelStart = todayLabelBefore ? todayX - 56 : todayX + 4;
  const tickUnderToday = (tick: { kind: string; leftPercent: number }) => {
    // A tick's label starts 8 px after its line and is about 24 px wide, a year about 32.
    const start = (tick.leftPercent / 100) * layout.canvasWidth + 8;
    const end = start + (tick.kind === "year" ? 32 : 24);
    return start < todayLabelStart + 52 && end > todayLabelStart;
  };
  const today = timelineToday(new Date(referenceDate), defaultTimezone);
  const yearGroups = useMemo(
    () => timelineYearGroups(items, today),
    [items, today],
  );
  const firstTimeCount =
    firstTimes.length + chapters.filter((item) => item.isFirstTime).length;
  const undated = items.filter((item) => !item.windowStart);
  const startYear = birthDate
    ? Number(birthDate.slice(0, 4))
    : items.reduce<number | null>((earliest, item) => {
        if (!item.windowStart) return earliest;
        const year = Number(item.windowStart.slice(0, 4));
        return earliest === null ? year : Math.min(earliest, year);
      }, null);
  const offerBirthDate = birthDateAvailable && !birthDate && !loadError;

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

  function changeZoom(next: TimelineZoom) {
    const element = viewport.current;

    if (element && element.clientWidth > 0) {
      // Keep today where it is when it is in view, or else the date in the middle.
      const start = Date.parse(layout.start);
      const range = Date.parse(layout.end) - start;
      const todayX = (layout.todayPercent / 100) * layout.canvasWidth;
      const todayFraction = (todayX - element.scrollLeft) / element.clientWidth;
      const fraction =
        todayFraction >= 0 && todayFraction <= 1 ? todayFraction : 0.5;
      const x = element.scrollLeft + element.clientWidth * fraction;
      scrollTarget.current = {
        fraction,
        time: start + (x / layout.canvasWidth) * range,
        type: "date",
      };
    }

    setZoom(next);
  }

  function scrollToToday() {
    const element = viewport.current;
    const behavior = prefersReducedMotion() ? "auto" : "smooth";

    if (element && element.clientWidth > 0) {
      element.scrollTo({
        behavior,
        left: todayScrollLeft(layout, element.clientWidth),
      });
      return;
    }

    todayRule.current?.scrollIntoView({ behavior, block: "center" });
  }

  return (
    <PageFrame width="full">
      <PageHeader
        title={<>Timeline</>}
        meta={
          <SeparatedList
            aria-label="Timeline summary"
            className={styles.summary}
          >
            <span>{countLabel(chapters.length, "Chapter")}</span>
            <span>{countLabel(firstTimeCount, "First Time")}</span>
            {startYear !== null ? <span>{startYear} to today</span> : null}
            {offerBirthDate ? (
              <button
                className={styles.metaAction}
                onClick={() => setShowBirthDatePrompt(true)}
                type="button"
              >
                Set birth date
              </button>
            ) : null}
          </SeparatedList>
        }
        action={
          loadError ? null : (
            <>
              <SegmentedControl
                className={styles.zoom}
                label="Zoom"
                onChange={changeZoom}
                options={zoomOptions}
                value={zoom}
              />
              {/* With nothing dated, the board already rests on today. */}
              {layout.positions.length > 0 ? (
                <Button
                  onClick={scrollToToday}
                  type="button"
                  variant="secondary"
                >
                  Today
                </Button>
              ) : null}
              <Button
                onClick={() => setSelection({ type: "chooser" })}
                type="button"
                variant="quiet"
              >
                <Icon name="plus" />
                <span>Add to Timeline</span>
              </Button>
            </>
          )
        }
      />

      {suggestion && !loadError ? (
        <div className={styles.suggestion}>
          <ChapterSuggestionCard
            ownerId={ownerId}
            suggestion={suggestion}
            tagOptions={tagOptions}
            timezone={defaultTimezone}
          />
        </div>
      ) : null}

      {loadError ? (
        <div className={styles.message} role="alert">
          <Icon name="clock" size={20} />
          <div>
            <strong>Timeline unavailable</strong>
            <p>{loadError}</p>
          </div>
        </div>
      ) : null}

      {!loadError ? (
        <>
          <section className={styles.board} aria-label="Timeline by year">
            <div
              className={styles.viewport}
              data-testid="timeline-viewport"
              ref={viewport}
            >
              <div className={styles.canvas} ref={canvas} style={canvasStyle}>
                <div className={styles.axis} data-testid="timeline-axis">
                  {ticks.map((tick) => (
                    <span
                      data-edge={tick.leftPercent === 100 ? "end" : undefined}
                      data-hidden={tickUnderToday(tick) ? "true" : undefined}
                      data-tick={tick.kind}
                      key={tick.key}
                      style={{ left: `${tick.leftPercent}%` }}
                    >
                      {tick.label}
                    </span>
                  ))}
                </div>
                {/* An empty board keeps its sentence clear of the grid. */}
                {items.length > 0 ? (
                  <div aria-hidden="true" className={styles.gridLines}>
                    {ticks.map((tick) => (
                      <span
                        data-tick={tick.kind}
                        key={tick.key}
                        style={{ left: `${tick.leftPercent}%` }}
                      />
                    ))}
                  </div>
                ) : null}

                {items.length === 0 ? (
                  <div className={styles.emptyBand}>
                    <TimelineEmptyState
                      onAdd={() => setSelection({ type: "chooser" })}
                    />
                  </div>
                ) : null}
                {shownBands.map(({ band, label, members }, index) => (
                  <BandRow
                    band={band}
                    items={members}
                    key={band}
                    label={label}
                    last={index === shownBands.length - 1}
                    layout={layout}
                    positions={positions}
                  />
                ))}
                <div
                  aria-hidden="true"
                  className={styles.todayLine}
                  data-label={todayLabelBefore ? "before" : "after"}
                  data-testid="timeline-today"
                >
                  <span>Today</span>
                </div>
                <span
                  aria-hidden="true"
                  className={styles.barProbe}
                  ref={barProbe}
                />
                <span
                  aria-hidden="true"
                  className={styles.pointProbe}
                  ref={pointProbe}
                />
              </div>
            </div>
          </section>

          <section
            aria-label="Timeline, newest first"
            className={styles.vertical}
          >
            {items.length === 0 ? (
              <TimelineEmptyState
                onAdd={() => setSelection({ type: "chooser" })}
              />
            ) : (
              <VerticalTimeline
                groups={yearGroups}
                today={today}
                todayRule={todayRule}
              />
            )}
          </section>

          {undated.length > 0 ? (
            <p className={styles.note}>
              {undated.length === 1
                ? "1 Entry has no calendar date and is not on the Timeline."
                : `${undated.length} Entries have no calendar date and are not on the Timeline.`}{" "}
              <Link href="/library">Find them in Library</Link>
            </p>
          ) : null}
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

      {offerBirthDate && showBirthDatePrompt ? (
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

function TimelineEmptyState({ onAdd }: { onAdd: () => void }) {
  return (
    <EmptyState
      icon={<Icon name="timeline" />}
      onClick={onAdd}
      title={<>Add a Chapter or a First Time to start your Timeline.</>}
    />
  );
}

function VerticalTimeline({
  groups,
  today,
  todayRule,
}: {
  groups: TimelineYearGroup[];
  today: string;
  todayRule: RefObject<HTMLLIElement | null>;
}) {
  const todayLabel = new Intl.DateTimeFormat("en-US", {
    day: "numeric",
    month: "short",
    timeZone: "UTC",
  }).format(new Date(`${today}T12:00:00Z`));

  return (
    <div className={styles.rail}>
      {groups.map((group) => {
        const rows = group.items.map((item) => (
          <li key={item.id}>
            <Link className={styles.verticalItem} href={wikiEntryHref(item)}>
              <span
                aria-hidden="true"
                className={item.isChapter ? styles.railBar : styles.railDot}
                data-ongoing={
                  item.isChapter && item.windowEnd === null ? "true" : undefined
                }
              />
              <span className={styles.verticalCopy}>
                <VerticalDate item={item} year={group.year} />
                <strong>
                  {item.isChapter && item.isFirstTime ? (
                    <span className={styles.firstTimeStar}>
                      <Icon name="star" size={12} />
                    </span>
                  ) : null}
                  {item.title}
                </strong>
              </span>
            </Link>
          </li>
        ));

        if (group.todayIndex !== null) {
          rows.splice(
            group.todayIndex,
            0,
            <li className={styles.todayRule} key="today" ref={todayRule}>
              <span>Today · {todayLabel}</span>
            </li>,
          );
        }

        return (
          <section
            aria-labelledby={`timeline-year-${group.year}`}
            className={styles.year}
            key={group.year}
          >
            <h2 id={`timeline-year-${group.year}`}>{group.year}</h2>
            <ol>{rows}</ol>
          </section>
        );
      })}
    </div>
  );
}

function VerticalDate({ item, year }: { item: TimelineItem; year: number }) {
  const label = timelineRowDateLabel(item, year);
  return label ? <small>{label}</small> : null;
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
  last,
  layout,
  positions,
}: {
  band: TimelineBand;
  items: TimelineItem[];
  label: string;
  last: boolean;
  layout: TimelineLayout;
  positions: Map<string, TimelineLayout["positions"][number]>;
}) {
  const rowCount = layout.rowCountByBand[band] ?? 1;

  return (
    <div
      className={styles.band}
      data-band={band}
      data-last={last ? "true" : undefined}
      style={{ "--band-rows": rowCount } as CSSProperties}
    >
      <h2 className={styles.bandLabel}>{label}</h2>
      <ul
        aria-label={label}
        className={styles.bandItems}
        data-testid="timeline-band"
      >
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
                  <span className={styles.itemTitleText}>{item.title}</span>
                </span>
              </Link>
            </li>
          );
        })}
      </ul>
    </div>
  );
}

// Where the view scrolls to show a target in the given layout.
function targetScrollLeft(
  target: ScrollTarget,
  layout: TimelineLayout,
  visibleWidth: number,
) {
  if (target.type === "today") return todayScrollLeft(layout, visibleWidth);
  const start = Date.parse(layout.start);
  const range = Date.parse(layout.end) - start;
  const x = ((target.time - start) / range) * layout.canvasWidth;
  return Math.max(0, x - visibleWidth * target.fraction);
}

function todayScrollLeft(layout: TimelineLayout, visibleWidth: number) {
  const todayX = (layout.todayPercent / 100) * layout.canvasWidth;
  return Math.max(0, todayX - visibleWidth * todayAnchor);
}

function prefersReducedMotion() {
  return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
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

// Tracks the viewport width, so an empty or short Timeline fills its board. The server and
// first render use the minimum canvas, which keeps hydration stable; the first measure runs
// before paint, so the measured layout is the first one seen.
function useCanvasFillWidth(viewport: RefObject<HTMLDivElement | null>) {
  const [width, setWidth] = useState(0);

  useLayoutEffect(() => {
    const element = viewport.current;
    if (!element) return;
    const measure = () => setWidth(element.getBoundingClientRect().width);
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(element);
    return () => observer.disconnect();
  }, [viewport]);

  return width;
}
