"use client";

import { useId, useState } from "react";

import type { OccurrenceDraft } from "@/lib/data/occurrence";
import {
  DatePickerField,
  type DatePickerGranularity,
} from "@/components/date-picker-field";
import { TimezoneSelect } from "@/components/timezone-select";
import styles from "./date-fields.module.css";

type Precision = OccurrenceDraft["precision"];
type Segment = "day" | "month" | "year" | "unsure";

const segments: { label: string; value: Segment }[] = [
  { label: "Day", value: "day" },
  { label: "Month", value: "month" },
  { label: "Year", value: "year" },
  { label: "Not sure", value: "unsure" },
];

// The editor offers how precisely the date is known. Exact times, day ranges, ages,
// and unknown dates remain stored precisions, reached through the toggles, the Not
// sure description, or an empty date.
function segmentOf(precision: Precision): Segment {
  if (precision === "month" || precision === "year") return precision;
  if (precision === "approximate" || precision === "age") return "unsure";
  return "day";
}

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
  // An unknown date is a Day left empty; any edit stores it as a Day again.
  const precision = value.precision === "unknown" ? "day" : value.precision;
  const segment = segmentOf(precision);
  const [unsurePrecision] = useState<Precision>(
    value.precision === "age" ? "age" : "approximate",
  );
  const [showDescription, setShowDescription] = useState(Boolean(value.label));
  const precisionLabelId = useId();
  const change = (patch: Partial<OccurrenceDraft>) =>
    onChange({ ...value, precision, ...patch });

  const exact = precision === "exact";
  const unsure = segment === "unsure";
  const spanEnd = span && !point;
  // Outside a Period, only a Day or Not sure date can end, and never with a time.
  const endToggle = !span && !point && (segment === "day" || unsure) && !exact;
  const endAdded =
    spanEnd ||
    precision === "range" ||
    (unsure && !span && !point && value.endMode === "date");
  const presentShown = spanEnd || precision === "range";
  const endMode = presentShown ? (value.endMode ?? "date") : "date";
  const timeToggle = segment === "day" && (span || precision !== "range");
  const timezoneShown = defaultTimezone === undefined || exact;
  const timezoneIsDefault = value.timezone === defaultTimezone;
  const granularity: DatePickerGranularity =
    segment === "month" || segment === "year" ? segment : "day";

  function changeSegment(next: Segment) {
    if (next === segment) return;
    const keepEnd = span || (!point && (next === "day" || next === "unsure"));
    const date = (text: string) => {
      if (next === "year") return text.slice(0, 4);
      if (next === "month") return text.length >= 7 ? text.slice(0, 7) : "";
      return text.length >= 10 ? text.slice(0, 10) : "";
    };
    const end = keepEnd ? date(value.end) : "";
    const nextPrecision: Precision =
      next === "unsure"
        ? unsurePrecision
        : next === "day" && end && !span
          ? "range"
          : next;
    change({
      precision: nextPrecision,
      start: date(value.start),
      end,
      endMode:
        next === "unsure" && !span && !end
          ? "present"
          : end
            ? "date"
            : (value.endMode ?? "date"),
    });
  }

  // The date stays, and a new time starts empty rather than at an invented hour.
  function toggleTime(on: boolean) {
    change({
      precision: on ? "exact" : "day",
      start: value.start.slice(0, 10),
      end: span ? value.end.slice(0, 10) : "",
    });
  }

  function toggleEnd(on: boolean) {
    change(
      unsure
        ? { end: "", endMode: on ? "date" : "present" }
        : { precision: on ? "range" : "day", end: "", endMode: "date" },
    );
  }

  return (
    <fieldset
      aria-labelledby={precisionLabelId}
      disabled={disabled}
      className={styles.occurrenceEditor}
      data-ui-field
    >
      <div className={styles.precision}>
        <span id={precisionLabelId}>Date</span>
        <div>
          {segments.map((option) => (
            <button
              aria-pressed={segment === option.value}
              className={
                segment === option.value ? styles.precisionActive : undefined
              }
              key={option.value}
              onClick={() => changeSegment(option.value)}
              type="button"
            >
              {option.label}
            </button>
          ))}
        </div>
      </div>
      <div className={styles.occurrenceDateArea}>
        <div className={`${styles.fieldRow} ${styles.occurrenceDateRow}`}>
          <DatePickerField
            disabled={disabled}
            granularity={granularity}
            includeTime={exact}
            key={`start-${segment}-${exact}`}
            label={startLabel(unsure, endAdded)}
            size="medium"
            value={value.start}
            onChange={(start) => change({ start })}
          />
          {endAdded && endMode !== "present" ? (
            <DatePickerField
              disabled={disabled}
              granularity={granularity}
              includeTime={exact}
              key={`end-${segment}-${exact}`}
              label="End date"
              size="medium"
              value={value.end}
              onChange={(end) => change({ end })}
            />
          ) : null}
          {timezoneShown ? (
            <label>
              <span>
                Time zone
                {defaultTimezone !== undefined ? (
                  <small>
                    {timezoneIsDefault
                      ? "Default from Settings"
                      : "Entry override"}
                  </small>
                ) : null}
              </span>
              <TimezoneSelect
                ariaLabel="Time zone"
                disabled={disabled}
                onChange={(event) => change({ timezone: event.target.value })}
                referenceDate={value.start}
                value={value.timezone}
              />
            </label>
          ) : null}
        </div>
        <div className={styles.dateToggles}>
          {timeToggle ? (
            <label className={styles.presentToggle}>
              <input
                checked={exact}
                onChange={(event) => toggleTime(event.target.checked)}
                type="checkbox"
              />
              <span>Add time</span>
            </label>
          ) : null}
          {endToggle ? (
            <label className={styles.presentToggle}>
              <input
                checked={endAdded}
                onChange={(event) => toggleEnd(event.target.checked)}
                type="checkbox"
              />
              <span>Add end date</span>
            </label>
          ) : null}
          {presentShown ? (
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
                Present <small>Still going on</small>
              </span>
            </label>
          ) : null}
          {!unsure ? (
            <label className={styles.presentToggle}>
              <input
                checked={showDescription || Boolean(value.label)}
                onChange={(event) => {
                  setShowDescription(event.target.checked);
                  if (!event.target.checked) change({ label: "" });
                }}
                type="checkbox"
              />
              <span>Add date description</span>
            </label>
          ) : null}
        </div>
      </div>
      {unsure || showDescription || value.label ? (
        <label>
          <span>
            Date description
            {unsure ? (
              <span aria-hidden="true" className={styles.requiredMark}>
                *
              </span>
            ) : null}
          </span>
          <input
            aria-label="Date description"
            maxLength={200}
            placeholder={descriptionPlaceholder(precision)}
            required={unsure}
            value={value.label}
            onChange={(e) => change({ label: e.target.value })}
          />
        </label>
      ) : null}
      <p>{helpText(precision)}</p>
    </fieldset>
  );
}

function startLabel(unsure: boolean, endAdded: boolean) {
  if (endAdded) return "Start date";
  return unsure ? "Roughly when" : "Occurred";
}

function helpText(precision: Precision) {
  if (precision === "exact")
    return "Daylight-saving changes use the selected time zone.";
  if (precision === "age" || precision === "approximate")
    return "Describe what you remember. A rough date is optional, and no birth date is inferred.";
  return "Leave the date empty if you don't know it.";
}

function descriptionPlaceholder(precision: Precision) {
  switch (precision) {
    case "exact":
      return "Context, e.g. just before sunrise";
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
    default:
      return "Context, e.g. my first day at the new job";
  }
}
