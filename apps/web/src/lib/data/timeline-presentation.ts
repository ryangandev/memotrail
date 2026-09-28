import { occurrenceLabel } from "@/lib/data/occurrence";
import type { TimelineEntry, TimelineTrack } from "@/lib/data/timeline";

export type TimelineDisplayItem = {
  entry: TimelineEntry;
  dateLabel: string;
  trackName: string;
  year: number | null;
};

export type TimelineDisplayModel = {
  dated: TimelineDisplayItem[];
  undated: TimelineDisplayItem[];
};

export function timelineEntryDateLabel(entry: TimelineEntry) {
  const label = occurrenceLabel({
    datePrecision: entry.datePrecision,
    occurredAt: entry.occurredStart,
    occurredEnd: entry.occurredEnd,
    occurredLabel: entry.occurredLabel,
    occurredTimezone: entry.occurredTimezone,
  });
  return entry.kind === "stage" &&
    entry.occurredStart &&
    !entry.occurredEnd &&
    !entry.occurredLabel &&
    entry.datePrecision !== "range"
    ? `${label} onward`
    : label;
}

export function timelineEntryTypeLabel(entry: TimelineEntry) {
  switch (entry.itemSubtype) {
    case "home":
      return "Home";
    case "vehicle":
      return "Vehicle";
    case "first_time":
      return "First Time";
    default:
      return entry.kind === "stage" ? "Period" : "Moment";
  }
}

export function timelineRecordedYear(entry: TimelineEntry): number | null {
  if (!entry.occurredStart) return null;
  const date = new Date(entry.occurredStart);
  if (Number.isNaN(date.getTime())) return null;
  try {
    return Number(
      new Intl.DateTimeFormat("en-US", {
        timeZone: entry.occurredTimezone,
        year: "numeric",
      }).format(date),
    );
  } catch {
    return date.getUTCFullYear();
  }
}

export function createTimelineDisplayModel(
  tracks: TimelineTrack[],
): TimelineDisplayModel {
  const items = tracks
    .flatMap((track) =>
      track.items.map((entry) => ({
        entry,
        dateLabel: timelineEntryDateLabel(entry),
        trackName: track.name,
        year: timelineRecordedYear(entry),
      })),
    )
    .sort((a, b) => {
      const first = a.entry.occurredStart
        ? Date.parse(a.entry.occurredStart)
        : Infinity;
      const second = b.entry.occurredStart
        ? Date.parse(b.entry.occurredStart)
        : Infinity;
      return (
        first - second ||
        a.trackName.localeCompare(b.trackName) ||
        a.entry.title.localeCompare(b.entry.title)
      );
    });

  return {
    dated: items.filter((item) => item.year !== null),
    undated: items.filter((item) => item.year === null),
  };
}

export function groupTimelineYears(model: TimelineDisplayModel) {
  const groups = new Map<number, TimelineDisplayItem[]>();
  for (const item of model.dated) {
    if (item.year === null) continue;
    const values = groups.get(item.year) ?? [];
    values.push(item);
    groups.set(item.year, values);
  }
  return [...groups.entries()].sort(([a], [b]) => a - b);
}
