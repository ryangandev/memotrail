"use client";

import Link from "next/link";
import { useEffect, useRef, useState, type CSSProperties } from "react";
import type { TimelineLayout } from "@/lib/data/timeline-layout";
import type { TimelineIdeaModel } from "../_shared/model";
import { timelineIdeaEntryHref } from "../_shared/model";
import styles from "./precision-ruler-timeline.module.css";

type PositionStyle = CSSProperties & {
  "--item-left": string;
  "--item-top": string;
  "--item-width": string;
};

export function PrecisionRulerTimeline({
  layout,
  model,
  path,
}: {
  layout: TimelineLayout;
  model: TimelineIdeaModel;
  path: string;
}) {
  const viewport = useRef<HTMLDivElement>(null);
  const [zoom, setZoom] = useState(1);
  const firstRecordPercent = model.dated.length
    ? (layout.positions.find(
        (position) => position.id === model.dated[0].entry.id,
      )?.leftPercent ?? layout.todayPercent)
    : layout.todayPercent;
  const [cursor, setCursor] = useState(Math.round(firstRecordPercent));
  const width = Math.round(layout.canvasWidth * zoom);
  const positions = new Map(
    layout.positions.map((position) => [position.id, position]),
  );
  const stageLanes = Math.max(
    0,
    ...model.dated
      .filter((item) => item.entry.kind === "stage")
      .map((item) => positions.get(item.entry.id)?.lane ?? 0),
  );
  const eventLanes = Math.max(
    0,
    ...model.dated
      .filter((item) => item.entry.kind === "event")
      .map((item) => positions.get(item.entry.id)?.lane ?? 0),
  );
  const axisY = 120 + stageLanes * 78;
  const height = axisY + 172 + eventLanes * 78;
  const start = Date.parse(layout.start);
  const end = Date.parse(layout.end);
  const cursorYear = new Date(
    start + ((end - start) * cursor) / 100,
  ).getUTCFullYear();

  function centerOn(percent: number, nextZoom = zoom) {
    if (!viewport.current) return;
    viewport.current.scrollLeft =
      (layout.canvasWidth * nextZoom * percent) / 100 -
      viewport.current.clientWidth / 2;
  }

  useEffect(() => {
    if (viewport.current) {
      viewport.current.scrollLeft =
        (layout.canvasWidth * firstRecordPercent) / 100 -
        viewport.current.clientWidth / 2;
    }
  }, [firstRecordPercent, layout.canvasWidth]);

  return (
    <>
      <div className={styles.controls}>
        <div className={styles.cursorControl}>
          <label htmlFor="ruler-cursor">Browse year</label>
          <strong>{cursorYear}</strong>
          <input
            id="ruler-cursor"
            max="100"
            min="0"
            onChange={(event) => {
              const value = Number(event.target.value);
              setCursor(value);
              centerOn(value);
            }}
            type="range"
            value={cursor}
          />
        </div>
        <div className={styles.zoomControl}>
          <label htmlFor="ruler-zoom">Zoom</label>
          <input
            id="ruler-zoom"
            max="2.5"
            min="1"
            onChange={(event) => {
              const value = Number(event.target.value);
              setZoom(value);
              centerOn(cursor, value);
            }}
            step="0.25"
            type="range"
            value={zoom}
          />
          <span>{zoom.toFixed(2)}×</span>
        </div>
      </div>
      <p className={styles.hint}>
        Scroll horizontally to browse. Dates on records keep their saved
        precision.
      </p>
      <section
        aria-label="Zoomable timeline ruler"
        className={styles.viewport}
        ref={viewport}
      >
        <div className={styles.canvas} style={{ height, width }}>
          {layout.yearMarkers.map((marker) => (
            <span
              aria-hidden="true"
              className={styles.yearTick}
              key={marker.year}
              style={{ left: `${marker.leftPercent}%`, top: axisY }}
            >
              <small>{marker.label}</small>
            </span>
          ))}
          <div className={styles.axis} style={{ top: axisY }} />
          {model.dated.map((item) => {
            const position = positions.get(item.entry.id);
            if (!position) return null;
            const period = item.entry.kind === "stage";
            const style: PositionStyle = {
              "--item-left": `${position.leftPercent}%`,
              "--item-top": `${period ? axisY - 85 - position.lane * 78 : axisY + 22 + position.lane * 78}px`,
              "--item-width": `${Math.max(106, (position.widthPercent / 100) * width)}px`,
            };
            return (
              <Link
                aria-label={`${item.entry.title}, ${item.dateLabel}, ${item.trackName}`}
                className={`${styles.item} ${period ? styles.period : styles.moment} ${["age", "approximate"].includes(item.entry.datePrecision) ? styles.uncertain : ""}`}
                href={timelineIdeaEntryHref(item.entry.id, path)}
                key={item.entry.id}
                style={style}
              >
                <strong>{item.entry.title}</strong>
                <small>{item.dateLabel}</small>
                <span>{item.trackName}</span>
              </Link>
            );
          })}
          <span
            aria-hidden="true"
            className={styles.playhead}
            style={{ left: `${cursor}%` }}
          />
        </div>
      </section>
      {model.undated.length ? (
        <section aria-labelledby="ruler-undated" className={styles.undated}>
          <h2 id="ruler-undated">Without a calendar position</h2>
          <div className={styles.undatedList}>
            {model.undated.map((item) => (
              <Link
                href={timelineIdeaEntryHref(item.entry.id, path)}
                key={item.entry.id}
              >
                <strong>{item.entry.title}</strong>
                <span>{item.dateLabel}</span>
                <small>{item.trackName}</small>
              </Link>
            ))}
          </div>
        </section>
      ) : null}
    </>
  );
}
