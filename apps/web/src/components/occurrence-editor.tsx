"use client";
import {
  occurrencePrecisions,
  occurrencePrecisionLabels,
  type OccurrenceDraft,
} from "@/lib/data/occurrence";
import { PrecisionDateField } from "@/components/precision-date-field";
import {
  commonTimezones,
  supportedTimezones,
  timezoneLabel,
} from "@/lib/data/timezones";
import styles from "@/app/page.module.css";
export function OccurrenceEditor({
  value,
  onChange,
  disabled,
  span = false,
  point = false,
}: {
  value: OccurrenceDraft;
  onChange: (value: OccurrenceDraft) => void;
  disabled: boolean;
  span?: boolean;
  point?: boolean;
}) {
  const change = (patch: Partial<OccurrenceDraft>) =>
    onChange({ ...value, ...patch });
  const calendar = value.precision !== "unknown";
  const bounded =
    !point &&
    (span || ["range", "approximate", "age"].includes(value.precision));
  const endMode = value.endMode ?? (value.end ? "date" : "present");
  const precisionOptions =
    point && value.precision !== "range"
      ? occurrencePrecisions.filter((precision) => precision !== "range")
      : occurrencePrecisions;
  const allTimezones = supportedTimezones();
  const commonTimezoneSet = new Set<string>(commonTimezones);
  const currentTimezoneIsListed = allTimezones.includes(value.timezone);
  return (
    <fieldset disabled={disabled} className={styles.occurrenceEditor}>
      <legend>When it happened</legend>
      <div className={styles.reviewFieldRow}>
        <label>
          <span>Date precision</span>
          <select
            aria-label="Date precision"
            value={value.precision}
            onChange={(e) =>
              change({
                precision: e.target.value as OccurrenceDraft["precision"],
                start: "",
                end: "",
                endMode: "present",
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
        <label>
          <span>Time zone</span>
          <select
            aria-label="Time zone"
            value={value.timezone}
            onChange={(e) => change({ timezone: e.target.value })}
          >
            {!currentTimezoneIsListed ? (
              <optgroup label="Current time zone">
                <option value={value.timezone}>
                  {timezoneLabel(value.timezone)}
                </option>
              </optgroup>
            ) : null}
            <optgroup label="Common time zones">
              {commonTimezones.map((timezone) => (
                <option key={timezone} value={timezone}>
                  {timezoneLabel(timezone)}
                </option>
              ))}
            </optgroup>
            <optgroup label="All time zones">
              {allTimezones
                .filter((timezone) => !commonTimezoneSet.has(timezone))
                .map((timezone) => (
                  <option key={timezone} value={timezone}>
                    {timezoneLabel(timezone)}
                  </option>
                ))}
            </optgroup>
          </select>
        </label>
      </div>
      {calendar && (
        <div className={styles.reviewFieldRow}>
          <PrecisionDateField
            disabled={disabled}
            key={`start-${value.precision}`}
            label={startLabel(value.precision, bounded)}
            precision={value.precision as Exclude<typeof value.precision, "unknown">}
            value={value.start}
            onChange={(start) => change({ start })}
          />
          {bounded && (
            <div className={styles.occurrenceEndField}>
              <div className={styles.occurrenceEndHeader}>
                <span>End date</span>
                <label className={styles.presentToggle}>
                  <input
                    checked={endMode === "present"}
                    onChange={(event) =>
                      change({
                        end: event.target.checked ? "" : value.end,
                        endMode: event.target.checked ? "present" : "date",
                      })
                    }
                    type="checkbox"
                  />
                  <span>Present</span>
                </label>
              </div>
              {endMode === "present" ? (
                <strong className={styles.presentDateField}>
                  Ongoing through present
                </strong>
              ) : (
                <PrecisionDateField
                  disabled={disabled}
                  hideLabel
                  key={`end-${value.precision}`}
                  label="End date"
                  precision={value.precision as Exclude<typeof value.precision, "unknown">}
                  value={value.end}
                  onChange={(end) => change({ end })}
                />
              )}
            </div>
          )}
        </div>
      )}
      <label>
        <span>
          Date description
          <small>
            {["age", "approximate"].includes(value.precision)
              ? "Required"
              : "Optional"}
          </small>
        </span>
        <input
          aria-label="Date description"
          maxLength={200}
          placeholder={descriptionPlaceholder(value.precision)}
          value={value.label}
          onChange={(e) => change({ label: e.target.value })}
        />
      </label>
      <p>
        {value.precision === "exact"
          ? "Choose both a calendar date and a local time. Daylight-saving changes use the selected time zone."
          : ["age", "approximate"].includes(value.precision)
            ? "Describe what you remember. A calendar anchor is optional, and no birth date is inferred."
            : value.precision === "range"
              ? "Choose Present when this period is still happening."
              : value.precision === "unknown"
                ? "No occurred date will be stored. Creation time is kept separately."
                : "Only the selected precision is shown. Unknown days or months are not presented as facts."}
      </p>
    </fieldset>
  );
}

function startLabel(
  precision: OccurrenceDraft["precision"],
  bounded: boolean,
) {
  if (["age", "approximate"].includes(precision))
    return "Calendar anchor (optional)";
  return bounded ? "Start date" : "Occurred";
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
