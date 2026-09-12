export type TimelineLayoutSource = {
  id: string;
  kind: "event" | "stage";
  occurredEnd: string | null;
  occurredStart: string | null;
  trackId: string;
};

export type TimelinePosition = {
  id: string;
  lane: number;
  leftPercent: number;
  widthPercent: number;
};

export type TimelineYearMarker = {
  label: string;
  leftPercent: number;
  year: number;
};

export type TimelineLayout = {
  end: string;
  laneCountByTrack: Record<string, number>;
  positions: TimelinePosition[];
  start: string;
  yearMarkers: TimelineYearMarker[];
};

const minimumRangeMilliseconds = 365 * 24 * 60 * 60 * 1_000;
const minimumStageWidthPercent = 1.2;
const minimumCollisionWidthPercent = 13;

export function createTimelineLayout(
  items: TimelineLayoutSource[],
  referenceDate = new Date(),
): TimelineLayout {
  const validReference = validTime(referenceDate.toISOString()) ?? Date.now();
  const normalized = items
    .map((item) => {
      const start = validTime(item.occurredStart);
      const explicitEnd = item.occurredEnd ? validTime(item.occurredEnd) : null;
      const end =
        item.kind === "stage"
          ? Math.max(start ?? validReference, explicitEnd ?? validReference)
          : start;

      return start === null || end === null ? null : { ...item, end, start };
    })
    .filter((item): item is NonNullable<typeof item> => item !== null);

  const currentYear = referenceDate.getUTCFullYear();
  let earliest = Date.UTC(currentYear, 0, 1);
  let latest = Date.UTC(currentYear + 1, 0, 1);

  if (normalized.length > 0) {
    earliest = Math.min(...normalized.map((item) => item.start));
    latest = Math.max(...normalized.map((item) => item.end));
    const rawRange = Math.max(latest - earliest, minimumRangeMilliseconds);
    const padding = Math.max(rawRange * 0.025, 30 * 24 * 60 * 60 * 1_000);
    earliest -= padding;
    latest += padding;

    if (latest - earliest < minimumRangeMilliseconds) {
      const difference = minimumRangeMilliseconds - (latest - earliest);
      earliest -= difference / 2;
      latest += difference / 2;
    }
  }

  const range = latest - earliest;
  const positions: TimelinePosition[] = [];
  const laneCountByTrack: Record<string, number> = {};
  const itemsByTrack = new Map<string, typeof normalized>();

  for (const item of normalized) {
    const trackItems = itemsByTrack.get(item.trackId) ?? [];
    trackItems.push(item);
    itemsByTrack.set(item.trackId, trackItems);
  }

  for (const [trackId, trackItems] of itemsByTrack) {
    const laneEnds: number[] = [];

    trackItems.sort((a, b) => a.start - b.start || a.end - b.end);

    for (const item of trackItems) {
      let lane = laneEnds.findIndex((laneEnd) => laneEnd <= item.start);

      if (lane === -1) {
        lane = laneEnds.length;
      }

      const visualEnd = Math.max(
        item.end,
        item.start + (range * minimumCollisionWidthPercent) / 100,
      );
      laneEnds[lane] = visualEnd;
      positions.push({
        id: item.id,
        lane,
        leftPercent: clamp(((item.start - earliest) / range) * 100),
        widthPercent:
          item.kind === "event"
            ? 0
            : Math.max(
                minimumStageWidthPercent,
                clamp(((item.end - item.start) / range) * 100),
              ),
      });
    }

    laneCountByTrack[trackId] = Math.max(1, laneEnds.length);
  }

  const yearMarkers: TimelineYearMarker[] = [];
  const firstYear = new Date(earliest).getUTCFullYear();
  const lastYear = new Date(latest).getUTCFullYear();

  for (let year = firstYear; year <= lastYear; year += 1) {
    const position = Date.UTC(year, 0, 1);

    if (position >= earliest && position <= latest) {
      yearMarkers.push({
        label: String(year),
        leftPercent: clamp(((position - earliest) / range) * 100),
        year,
      });
    }
  }

  return {
    end: new Date(latest).toISOString(),
    laneCountByTrack,
    positions,
    start: new Date(earliest).toISOString(),
    yearMarkers,
  };
}

function validTime(value: string | null) {
  if (value === null) return null;
  const time = new Date(value).getTime();
  return Number.isNaN(time) ? null : time;
}

function clamp(value: number) {
  return Math.max(0, Math.min(100, value));
}
