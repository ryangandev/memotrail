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
import type { Milestone, MilestoneLane } from "@/lib/data/milestone";
import type { TimelineLaneGroup } from "@/lib/data/timeline";
import {
  createTimelineLayout,
  estimateLabelWidth,
} from "@/lib/data/timeline-layout";
import { timelineEntryDateLabel } from "@/lib/data/timeline-presentation";
import { wikiEntryHref } from "@/lib/data/wiki-item";
import styles from "@/components/timeline-workspace.module.css";

const NewEntryDialog = dynamic(
  () =>
    import("@/components/entry-editor-dialog").then(
      (module) => module.NewEntryDialog,
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
  | { type: "milestone"; milestone: Milestone }
  | { type: "home" }
  | { type: "vehicle" };

type CreationType = "milestone" | "first-time" | "home" | "vehicle";

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
  defaultTimezone,
  lanes,
  loadError,
  ownerId,
  referenceDate,
  tagOptions,
}: {
  birthDate: string | null;
  birthDateAvailable: boolean;
  defaultTimezone: string;
  lanes: TimelineLaneGroup[];
  loadError: string | null;
  ownerId: string;
  referenceDate: string;
  tagOptions: string[];
}) {
  const [selection, setSelection] = useState<EditorSelection | null>(null);
  const [birthDate, setBirthDate] = useState(serverBirthDate);
  const [showBirthDatePrompt, setShowBirthDatePrompt] = useState(false);
  const items = useMemo(() => lanes.flatMap((lane) => lane.items), [lanes]);
  const labelProbe = useRef<HTMLSpanElement>(null);
  const measureLabel = useLabelMeasure(labelProbe);
  const viewport = useRef<HTMLDivElement>(null);
  const laneLabel = useRef<HTMLDivElement>(null);
  const fillWidth = useCanvasFillWidth(viewport, laneLabel);
  const layout = useMemo(
    () =>
      createTimelineLayout(
        items.map((item) => ({
          ...item,
          labelWidthPixels: measureLabel(item.title),
        })),
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
  const gridStyle: GridStyle = {
    "--timeline-canvas-width": `${layout.canvasWidth}px`,
    "--timeline-today-percent": layout.todayPercent,
  };

  function startCreation(type: CreationType, lane: MilestoneLane = "other") {
    if (type === "home" || type === "vehicle") {
      setSelection({ type });
      return;
    }
    setSelection({
      type: "milestone",
      milestone: {
        isFirstTime: type === "first-time",
        lane,
        shape: lane === "work_study" ? "period" : "moment",
      },
    });
  }

  function startCreationForLane(lane: TimelineLaneGroup) {
    if (lane.key === "homes") startCreation("home");
    else if (lane.key === "vehicles") startCreation("vehicle");
    else startCreation("milestone", lane.key);
  }

  function closeSelection() {
    setSelection(null);
  }

  return (
    <PageFrame variant="canvas">
      <PageHeader
        title={<>Timeline</>}
        eyebrow={<>Your life in context</>}
        description={
          <>See the places, vehicles, and milestones that shape your life.</>
        }
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
          <span>{itemCountLabel(items.length)}</span>
          {items.some((item) => item.occurredStart) ? (
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
            aria-label="Timeline by lane"
          >
            <div className={styles.timelineHint}>
              <span>Scroll across years</span>
              <small>Select anything to open it</small>
            </div>
            {items.some((item) => !item.occurredStart) ? (
              <section
                className={styles.undatedItems}
                aria-label="Without a calendar date"
              >
                <h2>Without a calendar date</h2>
                <p>These stay in their lanes without an invented year.</p>
                {lanes
                  .filter((lane) =>
                    lane.items.some((item) => !item.occurredStart),
                  )
                  .map((lane) => (
                    <div key={lane.key}>
                      <h3>{lane.name}</h3>
                      {lane.items
                        .filter((item) => !item.occurredStart)
                        .map((entry) => (
                          <Link href={wikiEntryHref(entry)} key={entry.id}>
                            {entry.title}, {timelineEntryDateLabel(entry)}
                          </Link>
                        ))}
                    </div>
                  ))}
              </section>
            ) : null}
            <div
              className={styles.timelineViewport}
              data-testid="timeline-viewport"
              ref={viewport}
            >
              <div className={styles.timelineGrid} style={gridStyle}>
                <div className={styles.axisCorner} ref={laneLabel}>
                  Lane
                </div>
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

                {lanes.map((lane) => (
                  <LaneRow
                    key={lane.key}
                    lane={lane}
                    layout={layout}
                    onAdd={() => startCreationForLane(lane)}
                    positions={positions}
                  />
                ))}
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
          </section>

          <section
            className={styles.mobileTimeline}
            aria-label="Timeline by lane"
          >
            {lanes.map((lane) => (
              <article className={styles.mobileLane} key={lane.key}>
                <header>
                  <div>
                    <h2>{lane.name}</h2>
                    <span>{itemCountLabel(lane.items.length)}</span>
                  </div>
                  <button
                    aria-label={addLabel(lane)}
                    onClick={() => startCreationForLane(lane)}
                    type="button"
                  >
                    <Icon name="plus" size={17} />
                  </button>
                </header>
                {lane.items.length === 0 ? (
                  <p className={styles.mobileEmpty}>{emptyLabel(lane)}</p>
                ) : (
                  <div className={styles.mobileItems}>
                    {lane.items.map((entry) => (
                      <Link href={wikiEntryHref(entry)} key={entry.id}>
                        <span
                          className={
                            entry.shape === "period"
                              ? styles.mobilePeriodMarker
                              : styles.mobileMomentMarker
                          }
                        />
                        <span>
                          <strong>{entry.title}</strong>
                          <small>{timelineEntryDateLabel(entry)}</small>
                        </span>
                        <Icon name="chevron" size={15} />
                      </Link>
                    ))}
                  </div>
                )}
              </article>
            ))}
          </section>
        </>
      ) : null}

      {selection?.type === "chooser" ? (
        <TimelineTypeChooser
          onClose={closeSelection}
          onSelect={(type) => startCreation(type)}
        />
      ) : null}

      {selection?.type === "milestone" ? (
        <NewEntryDialog
          milestone={selection.milestone}
          onClose={closeSelection}
          ownerId={ownerId}
          tagOptions={tagOptions}
          timezone={defaultTimezone}
        />
      ) : null}

      {selection?.type === "home" ? (
        <HomeEditor
          defaultTimezone={defaultTimezone}
          home={null}
          onClose={closeSelection}
          onSaved={() => undefined}
          onTrashed={() => undefined}
          ownerId={ownerId}
          tagOptions={tagOptions}
        />
      ) : null}

      {selection?.type === "vehicle" ? (
        <VehicleEditor
          defaultTimezone={defaultTimezone}
          onClose={closeSelection}
          onSaved={() => undefined}
          onTrashed={() => undefined}
          ownerId={ownerId}
          tagOptions={tagOptions}
          vehicle={null}
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
    icon: "timeline" | "home" | "car" | "star";
    label: string;
    type: CreationType;
  }[] = [
    {
      description: "A moment or a period worth marking, like a job or a trip.",
      icon: "timeline",
      label: "Milestone",
      type: "milestone",
    },
    {
      description: "A milestone that was the first time you did something.",
      icon: "star",
      label: "First Time",
      type: "first-time",
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

function LaneRow({
  lane,
  layout,
  onAdd,
  positions,
}: {
  lane: TimelineLaneGroup;
  layout: ReturnType<typeof createTimelineLayout>;
  onAdd: () => void;
  positions: Map<
    string,
    ReturnType<typeof createTimelineLayout>["positions"][number]
  >;
}) {
  const rowCount = layout.rowCountByLane[lane.key] ?? 1;
  const rowHeight = Math.max(70, rowCount * 49 + 20);

  return (
    <>
      <div className={styles.laneLabel} style={{ height: rowHeight }}>
        <span>
          <strong>{lane.name}</strong>
          <small>{lane.items.length || "Empty"}</small>
        </span>
        <button aria-label={addLabel(lane)} onClick={onAdd} type="button">
          <Icon name="plus" size={15} />
        </button>
      </div>
      <div
        className={styles.laneCanvas}
        data-testid="timeline-lane"
        style={{ height: rowHeight }}
      >
        {layout.yearMarkers.map((marker) => (
          <span
            aria-hidden="true"
            className={styles.yearLine}
            key={marker.year}
            style={{ left: `${marker.leftPercent}%` }}
          />
        ))}
        {lane.items.map((entry) => {
          const position = positions.get(entry.id);

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
          const dateLabel = timelineEntryDateLabel(entry);

          return (
            <Link
              aria-label={`${entry.title}, ${dateLabel}`}
              className={
                entry.shape === "period" ? styles.periodItem : styles.momentItem
              }
              data-label={position.labelPlacement}
              data-ongoing={
                entry.shape === "period" && entry.occurredEnd === null
                  ? "true"
                  : undefined
              }
              href={wikiEntryHref(entry)}
              key={entry.id}
              style={itemStyle}
              title={`${entry.title} · ${dateLabel}`}
            >
              {entry.shape === "moment" ? (
                <span className={styles.momentDot} />
              ) : position.labelPlacement === "inside" ? null : (
                <span className={styles.periodBar} />
              )}
              <span>{entry.title}</span>
            </Link>
          );
        })}
        {lane.items.length === 0 ? (
          <button className={styles.emptyLane} onClick={onAdd} type="button">
            {emptyLabel(lane)}
          </button>
        ) : null}
      </div>
    </>
  );
}

// Measures titles in the lane item font once it has loaded, so the layout knows which
// fit inside their Period. The server and first render estimate, which keeps hydration
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

// Tracks the width beside the lane labels, so an empty or short Timeline fills its card.
// The server and first render use the minimum canvas, which keeps hydration stable.
function useCanvasFillWidth(
  viewport: RefObject<HTMLDivElement | null>,
  laneLabel: RefObject<HTMLDivElement | null>,
) {
  const [width, setWidth] = useState(0);

  useEffect(() => {
    const element = viewport.current;
    const label = laneLabel.current;
    if (!element || !label) return;
    const observer = new ResizeObserver(() =>
      setWidth(
        element.getBoundingClientRect().width -
          label.getBoundingClientRect().width,
      ),
    );
    observer.observe(element);
    return () => observer.disconnect();
  }, [laneLabel, viewport]);

  return width;
}

function addLabel(lane: TimelineLaneGroup) {
  if (lane.key === "homes") return "Add a Home";
  if (lane.key === "vehicles") return "Add a Vehicle";
  return `Add a milestone to ${lane.name}`;
}

function emptyLabel(lane: TimelineLaneGroup) {
  if (lane.key === "homes") return "Add a place you lived";
  if (lane.key === "vehicles") return "Add a vehicle";
  return "Add the first milestone";
}

function rangeLabel(start: string, end: string) {
  return `${new Date(start).getUTCFullYear()} to ${new Date(end).getUTCFullYear()}`;
}

function itemCountLabel(count: number) {
  return `${count} ${count === 1 ? "item" : "items"}`;
}
