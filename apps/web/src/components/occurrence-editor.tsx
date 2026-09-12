"use client";
import {
  occurrencePrecisions,
  occurrencePrecisionLabels,
  type OccurrenceDraft,
} from "@/lib/data/occurrence";
import styles from "@/app/page.module.css";
export function OccurrenceEditor({
  value,
  onChange,
  disabled,
}: {
  value: OccurrenceDraft;
  onChange: (value: OccurrenceDraft) => void;
  disabled: boolean;
}) {
  const change = (patch: Partial<OccurrenceDraft>) =>
    onChange({ ...value, ...patch });
  const calendar = value.precision !== "unknown";
  const bounded = ["range", "approximate", "age"].includes(value.precision);
  return (
    <fieldset disabled={disabled} className={styles.occurrenceEditor}>
      <legend>When it happened</legend>
      <div className={styles.reviewFieldRow}>
        <label>
          <span>Date precision</span>
          <select
            value={value.precision}
            onChange={(e) =>
              change({
                precision: e.target.value as OccurrenceDraft["precision"],
                start: "",
                end: "",
              })
            }
          >
            {occurrencePrecisions.map((p) => (
              <option key={p} value={p}>
                {occurrencePrecisionLabels[p]}
              </option>
            ))}
          </select>
        </label>
        <label>
          <span>Time zone</span>
          <input
            value={value.timezone}
            onChange={(e) => change({ timezone: e.target.value })}
            placeholder="America/Los_Angeles"
          />
        </label>
      </div>
      {calendar && (
        <div className={styles.reviewFieldRow}>
          <label>
            <span>
              {value.precision === "range"
                ? "Start date"
                : bounded
                  ? "Start date (optional)"
                  : "Occurred"}
            </span>
            <input
              aria-label="Occurred"
              type={
                value.precision === "exact"
                  ? "datetime-local"
                  : value.precision === "month"
                    ? "month"
                    : value.precision === "year"
                      ? "text"
                      : "date"
              }
              step={value.precision === "exact" ? "1" : undefined}
              placeholder={value.precision === "year" ? "YYYY" : undefined}
              value={value.start}
              onChange={(e) => change({ start: e.target.value })}
            />
          </label>
          {bounded && (
            <label>
              <span>End date (optional)</span>
              <input
                type="date"
                value={value.end}
                onChange={(e) => change({ end: e.target.value })}
              />
            </label>
          )}
        </div>
      )}
      <label>
        <span>Date description</span>
        <input
          maxLength={200}
          placeholder={
            value.precision === "age"
              ? "At age 17"
              : "Optional, e.g. summer before college"
          }
          value={value.label}
          onChange={(e) => change({ label: e.target.value })}
        />
      </label>
      <p>
        {value.precision === "exact"
          ? "Times use the recorded time zone. A repeated daylight-saving hour uses its earlier occurrence when edited."
          : ["age", "approximate"].includes(value.precision)
            ? "A description is enough. Calendar dates are optional; no birth date is inferred."
            : value.precision === "range"
              ? "Leave the end date empty when the period continues."
              : value.precision === "unknown"
                ? "No occurred date will be stored. Creation time is kept separately."
                : "Only the selected precision is shown. Unknown days or months are not presented as facts."}
      </p>
    </fieldset>
  );
}
