"use client";

import { useState } from "react";
import {
  occurrencePrecisions,
  occurrencePrecisionLabels,
  type OccurrenceDraft,
} from "@/lib/data/occurrence";
import { PrecisionDateField } from "@/components/precision-date-field";
import { TimezoneSelect } from "@/components/timezone-select";
import { timezoneLabel } from "@/lib/data/timezones";
import styles from "@/app/page.module.css";

export function OccurrenceEditor({
  value,
  onChange,
  disabled,
  defaultTimezone,
  span = false,
  point = false,
}: {
  value: OccurrenceDraft;
  onChange: (value: OccurrenceDraft) => void;
  disabled: boolean;
  defaultTimezone?: string;
  span?: boolean;
  point?: boolean;
}) {
  const [editingTimezone, setEditingTimezone] = useState(false);
  const change = (patch: Partial<OccurrenceDraft>) =>
    onChange({ ...value, ...patch });
  const calendar = value.precision !== "unknown";
  const bounded =
    !point &&
    (span || ["range", "approximate", "age"].includes(value.precision));
  const endMode = value.endMode ?? "date";
  const descriptionRequired = ["age", "approximate"].includes(value.precision);
  const startRequired =
    calendar && !["age", "approximate"].includes(value.precision);
  const precisionOptions =
    point && value.precision !== "range"
      ? occurrencePrecisions.filter((precision) => precision !== "range")
      : occurrencePrecisions;
  const precisionHelp = helpText(value.precision);
  const timezoneIsDefault = value.timezone === defaultTimezone;
  return (
    <fieldset disabled={disabled} className={styles.occurrenceEditor}>
      <legend>When it happened</legend>
      <div className={styles.reviewFieldRow}>
        <label>
          <span>
            Date type
            <span aria-hidden="true" className={styles.requiredMark}>
              *
            </span>
          </span>
          <select
            aria-label="Date type"
            required
            value={value.precision}
            onChange={(e) =>
              change({
                precision: e.target.value as OccurrenceDraft["precision"],
                start: "",
                end: "",
                endMode: "date",
              })
            }
          >
            {precisionOptions.map((p) => (
              <option key={p} value={p}>
                {occurrencePrecisionLabels[p]}
              </option>
            ))}
          </select>
        </label>
        {defaultTimezone ? (
          value.precision === "exact" ? (
            !editingTimezone ? (
              <div className={styles.timezoneSummary}>
                <span>Time zone</span>
                <div>
                  <span>
                    <strong>{timezoneLabel(value.timezone)}</strong>
                    <small>
                      {timezoneIsDefault
                        ? "Default from Settings"
                        : "Entry override"}
                    </small>
                  </span>
                  <button
                    disabled={disabled}
                    onClick={() => setEditingTimezone(true)}
                    type="button"
                  >
                    Change
                  </button>
                </div>
              </div>
            ) : (
              <label>
                <span>Time zone</span>
                <TimezoneSelect
                  ariaLabel="Time zone"
                  disabled={disabled}
                  onChange={(event) => change({ timezone: event.target.value })}
                  value={value.timezone}
                />
              </label>
            )
          ) : null
        ) : (
          <label>
            <span>Time zone</span>
            <TimezoneSelect
              ariaLabel="Time zone"
              disabled={disabled}
              onChange={(event) => change({ timezone: event.target.value })}
              value={value.timezone}
            />
          </label>
        )}
      </div>
      {calendar && (
        <div className={styles.occurrenceDateArea}>
          <div
            className={`${styles.reviewFieldRow} ${styles.occurrenceDateRow}`}
          >
            <PrecisionDateField
              disabled={disabled}
              key={`start-${value.precision}`}
              label={startLabel(value.precision, bounded)}
              precision={
                value.precision as Exclude<typeof value.precision, "unknown">
              }
              required={startRequired}
              value={value.start}
              onChange={(start) => change({ start })}
            />
            {bounded && endMode !== "present" ? (
              <PrecisionDateField
                disabled={disabled}
                key={`end-${value.precision}`}
                label="End date"
                precision={
                  value.precision as Exclude<typeof value.precision, "unknown">
                }
                value={value.end}
                onChange={(end) => change({ end })}
              />
            ) : null}
          </div>
          {bounded ? (
            <label className={styles.presentToggle}>
              <input
                aria-label="Present"
                checked={endMode === "present"}
                onChange={(event) =>
                  change({
                    end: event.target.checked ? "" : value.end,
                    endMode: event.target.checked ? "present" : "date",
                  })
                }
                type="checkbox"
              />
              <span>
                Present <small>This period is still ongoing</small>
              </span>
            </label>
          ) : null}
        </div>
      )}
      <label>
        <span>
          Date description
          {descriptionRequired ? (
            <span aria-hidden="true" className={styles.requiredMark}>
              *
            </span>
          ) : null}
        </span>
        <input
          aria-label="Date description"
          maxLength={200}
          placeholder={descriptionPlaceholder(value.precision)}
          required={descriptionRequired}
          value={value.label}
          onChange={(e) => change({ label: e.target.value })}
        />
      </label>
      {precisionHelp ? <p>{precisionHelp}</p> : null}
    </fieldset>
  );
}

function startLabel(precision: OccurrenceDraft["precision"], bounded: boolean) {
  if (["age", "approximate"].includes(precision)) return "Start date";
  return bounded ? "Start date" : "Occurred";
}

function helpText(precision: OccurrenceDraft["precision"]) {
  if (precision === "exact")
    return "Choose both a calendar date and a local time. Daylight-saving changes use the selected time zone.";
  if (["age", "approximate"].includes(precision))
    return "Describe what you remember. A start date can add calendar context, and no birth date is inferred.";
  if (precision === "range") return null;
  if (precision === "unknown")
    return "No occurred date will be stored. Creation time is kept separately.";
  return "Only the selected date type is shown. Unknown days or months are not presented as facts.";
}

function descriptionPlaceholder(precision: OccurrenceDraft["precision"]) {
  switch (precision) {
    case "exact":
      return "Context, e.g. just before sunrise";
    case "day":
      return "Context, e.g. my first day at the new job";
    case "month":
      return "Context, e.g. early September";
    case "year":
      return "Context, e.g. the year I moved away";
    case "approximate":
      return "e.g. summer before college";
    case "age":
      return "e.g. age 17 or ages 17 to 19";
    case "range":
      return "Context, e.g. my years in Philadelphia";
    case "unknown":
      return "Anything you remember, e.g. sometime in childhood";
  }
}
