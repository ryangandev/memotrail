import { occurrenceLabel } from "@/lib/data/occurrence";
import type { TimelineEntry, TimelineTrack } from "@/lib/data/timeline";

export type TimelineIdeaItem = {
  entry: TimelineEntry;
  dateLabel: string;
  trackName: string;
  year: number | null;
};

export type TimelineIdeaModel = {
  items: TimelineIdeaItem[];
  dated: TimelineIdeaItem[];
  undated: TimelineIdeaItem[];
  tracks: TimelineTrack[];
};

function recordedYear(entry: TimelineEntry): number | null {
  if (!entry.occurredStart) return null;
  const date = new Date(entry.occurredStart);
  if (Number.isNaN(date.getTime())) return null;
  return Number(
    new Intl.DateTimeFormat("en-US", {
      timeZone: entry.occurredTimezone,
      year: "numeric",
    }).format(date),
  );
}

export function timelineIdeaDateLabel(entry: TimelineEntry) {
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

export function createTimelineIdeaModel(
  tracks: TimelineTrack[],
): TimelineIdeaModel {
  const items = tracks
    .flatMap((track) =>
      track.items.map((entry) => ({
        entry,
        dateLabel: timelineIdeaDateLabel(entry),
        trackName: track.name,
        year: recordedYear(entry),
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
    items,
    dated: items.filter((item) => item.year !== null),
    undated: items.filter((item) => item.year === null),
    tracks,
  };
}

export function timelineIdeaEntryHref(entryId: string, path: string) {
  return `/timeline?entry=${encodeURIComponent(entryId)}&returnTo=${encodeURIComponent(path)}`;
}

export function timelineIdeaCreateHref(path: string) {
  return `/timeline?new=1&returnTo=${encodeURIComponent(path)}`;
}
