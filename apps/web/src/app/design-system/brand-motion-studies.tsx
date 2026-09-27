"use client";

import { useState, type CSSProperties } from "react";
import { Badge } from "@/components/badge";
import { BrandMark } from "@/components/brand-mark";
import { Button } from "@/components/button";
import { Icon } from "@/components/icon";
import styles from "./brand-motion-studies.module.css";

const studies = [
  {
    id: "gentle",
    title: "Gentle turn",
    description:
      "The entire mark turns 90°. A quiet, direct response to the panel changing size.",
    timing: "240 ms",
  },
  {
    id: "counter",
    title: "Counter rotation",
    description:
      "The outer ring and warm accent turn together while the inner ring turns in the opposite direction.",
    timing: "320 ms",
  },
  {
    id: "relay",
    title: "Layered orbit",
    description:
      "The outer ring and accent orbit together. The inner ring follows, then all three return to the original mark.",
    timing: "420 ms",
  },
] as const;

type StudyId = (typeof studies)[number]["id"];
type PreviewState = Record<StudyId, { collapsed: boolean; cycle: number }>;

export function BrandMotionStudies() {
  const [previews, setPreviews] = useState<PreviewState>({
    gentle: { collapsed: false, cycle: 0 },
    counter: { collapsed: false, cycle: 0 },
    relay: { collapsed: false, cycle: 0 },
  });
  const allCollapsed = studies.every(({ id }) => previews[id].collapsed);

  function toggle(id: StudyId) {
    setPreviews((current) => ({
      ...current,
      [id]: {
        collapsed: !current[id].collapsed,
        cycle: current[id].cycle + 1,
      },
    }));
  }

  function toggleAll() {
    setPreviews(
      (current) =>
        Object.fromEntries(
          studies.map(({ id }) => [
            id,
            { collapsed: !allCollapsed, cycle: current[id].cycle + 1 },
          ]),
        ) as PreviewState,
    );
  }

  return (
    <div className={styles.studies}>
      <div className={styles.toolbar}>
        <p>Try each direction at study size and the 29px sidebar size.</p>
        <Button onClick={toggleAll} size="small" variant="secondary">
          {allCollapsed ? "Expand all previews" : "Collapse all previews"}
        </Button>
      </div>
      <div className={styles.grid}>
        {studies.map((study, index) => {
          const preview = previews[study.id];
          const markClass = `${styles.mark} ${styles[study.id]}`;
          const markKey = study.id === "relay" ? preview.cycle : undefined;

          return (
            <article
              aria-labelledby={`brand-motion-${study.id}`}
              className={styles.study}
              data-brand-motion-study={study.id}
              data-collapsed={preview.collapsed}
              data-played={preview.cycle > 0}
              key={study.id}
              style={
                {
                  "--brand-turn-direction": preview.collapsed ? 1 : -1,
                } as CSSProperties
              }
            >
              <header className={styles.heading}>
                <h4 id={`brand-motion-${study.id}`}>
                  <span>0{index + 1}</span> {study.title}
                </h4>
                <Badge size="micro" tone="neutral">
                  {study.timing}
                </Badge>
              </header>
              <div className={styles.stage}>
                <div className={styles.magnified}>
                  <BrandMark className={markClass} key={markKey} />
                </div>
                <div className={styles.rail}>
                  <div className={styles.railHeader}>
                    <BrandMark
                      className={`${markClass} ${styles.railMark}`}
                      key={markKey}
                    />
                    <span className={styles.wordmark}>MemoTrail</span>
                  </div>
                  <div className={styles.railItem}>
                    <Icon name="dashboard" size={18} />
                    <span>Dashboard</span>
                  </div>
                </div>
              </div>
              <p className={styles.description}>{study.description}</p>
              <div className={styles.controls}>
                <Badge size="micro" tone="outline">
                  {preview.collapsed ? "Collapsed" : "Expanded"}
                </Badge>
                <Button
                  aria-label={`${preview.collapsed ? "Expand" : "Collapse"} ${study.title} preview`}
                  onClick={() => toggle(study.id)}
                  size="small"
                  variant="secondary"
                >
                  <Icon
                    name={preview.collapsed ? "sidebarClosed" : "sidebarOpen"}
                    size={16}
                  />
                  {preview.collapsed ? "Expand" : "Collapse"}
                </Button>
              </div>
            </article>
          );
        })}
      </div>
      <p className={styles.reducedMotionNote}>
        Reduced motion is on. The previews change state without rotation.
      </p>
    </div>
  );
}
