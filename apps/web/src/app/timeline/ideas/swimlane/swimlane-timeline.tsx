import Link from "next/link";
import type { CSSProperties } from "react";
import { createTimelineLayout } from "@/lib/data/timeline-layout";
import type { TimelineIdeaItem, TimelineIdeaModel } from "../_shared/model";
import { timelineIdeaEntryHref } from "../_shared/model";
import { SwimlaneViewport } from "./swimlane-viewport";
import styles from "./swimlane-timeline.module.css";

type TimelineStyle = CSSProperties & {
  "--canvas-width": string;
  "--today-offset": string;
};

type ItemStyle = CSSProperties & {
  "--item-left": string;
  "--item-top": string;
  "--item-width": string;
};

export function SwimlaneTimeline({
  birthDate,
  model,
  path,
}: {
  birthDate: string | null;
  model: TimelineIdeaModel;
  path: string;
}) {
  const layout = createTimelineLayout(
    model.items.map(({ entry }) => entry),
    new Date(),
    birthDate,
  );
  const positions = new Map(
    layout.positions.map((position) => [position.id, position]),
  );
  const gridStyle: TimelineStyle = {
    "--canvas-width": `${layout.canvasWidth}px`,
    "--today-offset": `${(layout.todayPercent / 100) * layout.canvasWidth}px`,
  };
  const firstRecordOffset = model.dated.length
    ? ((positions.get(model.dated[0].entry.id)?.leftPercent ?? 0) / 100) *
      layout.canvasWidth
    : null;

  return (
    <>
      <div className={styles.key}>
        <span>
          <i className={styles.momentKey} /> Moment
        </span>
        <span>
          <i className={styles.periodKey} /> Period or focused record span
        </span>
        <span>
          <i className={styles.uncertainKey} /> Approximate date
        </span>
      </div>
      <p className={styles.hint}>Scroll across years to compare your tracks.</p>
      <SwimlaneViewport
        className={styles.viewport}
        firstRecordOffset={firstRecordOffset}
      >
        <div className={styles.grid} style={gridStyle}>
          <div className={styles.axisLabel}>Track</div>
          <div aria-label="Year axis" className={styles.axis}>
            {layout.yearMarkers.map((marker) => (
              <span
                key={marker.year}
                style={{ left: `${marker.leftPercent}%` }}
              >
                {marker.label}
              </span>
            ))}
          </div>
          {model.tracks.map((track) => {
            const laneCount = layout.laneCountByTrack[track.id] ?? 1;
            return (
              <div className={styles.trackRow} key={track.id}>
                <div className={styles.trackName}>
                  <strong>{track.name}</strong>
                  <small>{track.items.length} records</small>
                </div>
                <div
                  className={styles.trackCanvas}
                  style={{ height: `${Math.max(88, laneCount * 88)}px` }}
                >
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
                    if (!position) return null;
                    const item = model.items.find(
                      (candidate) => candidate.entry.id === entry.id,
                    );
                    if (!item) return null;
                    const style: ItemStyle = {
                      "--item-left": `calc(${position.leftPercent}% + ${position.stageLabelOffsetPixels}px)`,
                      "--item-top": `${position.lane * 88 + 9}px`,
                      "--item-width": `${Math.max(54, position.widthPixels)}px`,
                    };
                    return (
                      <Link
                        aria-label={`${entry.title}, ${item.dateLabel}, ${track.name}`}
                        className={`${styles.item} ${entry.kind === "stage" ? styles.period : styles.moment} ${["age", "approximate"].includes(entry.datePrecision) ? styles.uncertain : ""}`}
                        href={timelineIdeaEntryHref(entry.id, path)}
                        key={entry.id}
                        style={style}
                        title={`${entry.title} · ${item.dateLabel}`}
                      >
                        <strong>{entry.title}</strong>
                        <small>{item.dateLabel}</small>
                      </Link>
                    );
                  })}
                </div>
              </div>
            );
          })}
          <span aria-hidden="true" className={styles.todayLine} />
        </div>
      </SwimlaneViewport>
      {model.undated.length ? (
        <section aria-labelledby="swimlane-undated" className={styles.undated}>
          <h2 id="swimlane-undated">Without a calendar position</h2>
          <p>
            Age, approximate, and unknown dates stay visible without an invented
            year.
          </p>
          <div className={styles.undatedList}>
            {model.undated.map((item: TimelineIdeaItem) => (
              <Link
                href={timelineIdeaEntryHref(item.entry.id, path)}
                key={item.entry.id}
              >
                <span>{item.trackName}</span>
                <strong>{item.entry.title}</strong>
                <small>{item.dateLabel}</small>
              </Link>
            ))}
          </div>
        </section>
      ) : null}
    </>
  );
}
