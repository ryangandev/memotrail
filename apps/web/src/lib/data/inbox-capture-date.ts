import {
  occurrenceDraft,
  resolveOccurrenceDraft,
  type Occurrence,
  type OccurrenceDraft,
} from "./occurrence";

// The composer's date is a calendar day with an optional time; the Entry editor
// owns every other precision. It is kept in the shared draft as an ordinary
// occurrence draft, so drafts saved by earlier composers still load.

/**
 * The composer's Date field value for a draft: `YYYY-MM-DD`, or
 * `YYYY-MM-DDTHH:MM` with a time. A draft an earlier composer saved at another
 * precision shows its day when it has one, and is empty otherwise.
 */
export function captureDateValue(draft: OccurrenceDraft): string {
  if (draft.precision === "exact") return draft.start.slice(0, 16);
  if (draft.precision === "day") return draft.start;
  return /^\d{4}-\d{2}-\d{2}/.test(draft.start) ? draft.start.slice(0, 10) : "";
}

/** The draft for a Date field value: a Day, or an exact time once a time is set. */
export function captureDateDraft(
  value: string,
  timezone: string,
): OccurrenceDraft {
  return {
    precision: value.includes("T") ? "exact" : "day",
    start: value,
    end: "",
    label: "",
    timezone,
  };
}

/** Today in the capture's time zone, the day a newly opened Date starts on. */
export function todayCaptureDate(now: Date, timezone: string) {
  const { start } = occurrenceDraft({
    datePrecision: "day",
    occurredAt: now.toISOString(),
    occurredEnd: null,
    occurredLabel: null,
    occurredTimezone: timezone,
  });
  return captureDateDraft(start, timezone);
}

/**
 * The date a capture saves with: the chosen day or time, or the capture time
 * itself when no day is chosen.
 */
export function resolveCaptureDate(
  draft: OccurrenceDraft | null,
  now: Date,
  timezone: string,
): { value: Occurrence; error?: never } | { error: string; value?: never } {
  const value = draft ? captureDateValue(draft) : "";
  if (!draft || !value)
    return {
      value: {
        datePrecision: "exact",
        occurredAt: now.toISOString(),
        occurredEnd: null,
        occurredLabel: null,
        occurredTimezone: timezone,
      },
    };
  return resolveOccurrenceDraft(captureDateDraft(value, draft.timezone));
}
