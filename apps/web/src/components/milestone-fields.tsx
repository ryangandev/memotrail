"use client";

import { Icon } from "@/components/icon";
import {
  milestoneLanes,
  timelineLaneLabels,
  type Milestone,
  type MilestoneLane,
  type MilestoneShape,
} from "@/lib/data/milestone";
import styles from "./milestone-fields.module.css";

const defaultMilestone: Milestone = {
  isFirstTime: false,
  lane: "other",
  shape: "moment",
};

// Marks an Entry as a life milestone on Timeline: a Moment or a Period, its lane, and
// whether it was a First Time.
export function MilestoneFields({
  disabled,
  onChange,
  value,
}: {
  disabled: boolean;
  onChange: (value: Milestone | null) => void;
  value: Milestone | null;
}) {
  const change = (patch: Partial<Milestone>) =>
    onChange({ ...(value ?? defaultMilestone), ...patch });

  return (
    <fieldset
      aria-label="Timeline"
      className={styles.milestone}
      data-ui-field
      disabled={disabled}
    >
      <label className={styles.toggle}>
        <input
          checked={value !== null}
          onChange={(event) =>
            onChange(event.target.checked ? defaultMilestone : null)
          }
          type="checkbox"
        />
        <span>
          Show on Timeline
          <small>Mark this as a milestone in your life</small>
        </span>
      </label>
      {value ? (
        <div className={styles.details}>
          <div className={styles.shape}>
            <span id="milestone-shape-label">Shape</span>
            <div aria-labelledby="milestone-shape-label" role="group">
              {(["moment", "period"] as MilestoneShape[]).map((shape) => (
                <button
                  aria-pressed={value.shape === shape}
                  className={
                    value.shape === shape ? styles.shapeActive : undefined
                  }
                  key={shape}
                  onClick={() => change({ shape })}
                  type="button"
                >
                  <Icon
                    name={shape === "period" ? "timeline" : "star"}
                    size={16}
                  />
                  {shape === "period" ? "Period" : "Moment"}
                </button>
              ))}
            </div>
            <p>
              {value.shape === "period"
                ? "A stretch of time that may still be going on."
                : "One point in time."}
            </p>
          </div>
          {/* A native select, like Date type below, so the Entry form reads as one. */}
          <label className={styles.lane}>
            <span>Lane</span>
            <select
              onChange={(event) =>
                change({ lane: event.target.value as MilestoneLane })
              }
              value={value.lane}
            >
              {milestoneLanes.map((lane) => (
                <option key={lane} value={lane}>
                  {timelineLaneLabels[lane]}
                </option>
              ))}
            </select>
          </label>
          <label className={styles.toggle}>
            <input
              checked={value.isFirstTime}
              onChange={(event) =>
                change({ isFirstTime: event.target.checked })
              }
              type="checkbox"
            />
            <span>
              First Time
              <small>Also list it in First Times</small>
            </span>
          </label>
        </div>
      ) : null}
    </fieldset>
  );
}
