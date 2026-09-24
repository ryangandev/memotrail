import type { FirstTimeEntry } from "./first-times";
import type { TimelineEntry, TimelineTrack } from "./timeline";

// First Times saved from their focused editor do not create a Timeline placement.
// Project dated, unplaced records onto the visible system track without changing
// their stored organization or duplicating records already placed elsewhere.
export function includeUnplacedFirstTimes(
  tracks: TimelineTrack[],
  firstTimes: FirstTimeEntry[],
): TimelineTrack[] {
  const firstTimesTrack = tracks.find(
    (track) => track.systemKey === "first_times",
  );
  if (!firstTimesTrack) return tracks;

  const placedIds = new Set(
    tracks.flatMap((track) => track.items.map((item) => item.id)),
  );
  const projected: TimelineEntry[] = firstTimes
    .filter((entry) => entry.occurredStart && !placedIds.has(entry.id))
    .map((entry) => ({
      body: entry.body,
      collectionNames: entry.collectionNames,
      datePrecision: entry.datePrecision,
      id: entry.id,
      itemKind: "event",
      itemSubtype: "first_time",
      kind: "event",
      occurredEnd: entry.occurredEnd,
      occurredLabel: entry.occurredLabel,
      occurredStart: entry.occurredStart,
      occurredTimezone: entry.occurredTimezone ?? "UTC",
      revision: entry.revision,
      tagNames: entry.tagNames,
      title: entry.title,
      trackId: firstTimesTrack.id,
      updatedAt: entry.updatedAt,
    }));
  if (projected.length === 0) return tracks;

  return tracks.map((track) =>
    track.id === firstTimesTrack.id
      ? {
          ...track,
          items: [...track.items, ...projected].sort(
            (a, b) =>
              (a.occurredStart ? Date.parse(a.occurredStart) : Infinity) -
                (b.occurredStart ? Date.parse(b.occurredStart) : Infinity) ||
              a.title.localeCompare(b.title),
          ),
        }
      : track,
  );
}
