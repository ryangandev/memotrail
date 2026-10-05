import { occurrenceLabel } from "@/lib/data/occurrence";
import type { TimelineEntry } from "@/lib/data/timeline";

export function timelineEntryDateLabel(entry: TimelineEntry) {
  const label = occurrenceLabel({
    datePrecision: entry.datePrecision,
    occurredAt: entry.occurredStart,
    occurredEnd: entry.occurredEnd,
    occurredLabel: entry.occurredLabel,
    occurredTimezone: entry.occurredTimezone,
  });
  return entry.shape === "period" &&
    entry.occurredStart &&
    !entry.occurredEnd &&
    !entry.occurredLabel &&
    entry.datePrecision !== "range"
    ? `${label} onward`
    : label;
}
