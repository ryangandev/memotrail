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
  stageLabelOffsetPixels: number;
  widthPixels: number;
  widthPercent: number;
};

export type TimelineYearMarker = {
  label: string;
  leftPercent: number;
  year: number;
};

export type TimelineLayout = {
  canvasWidth: number;
  end: string;
  laneCountByTrack: Record<string, number>;
  positions: TimelinePosition[];
  start: string;
  yearMarkers: TimelineYearMarker[];
};

const minimumRangeMilliseconds = 365 * 24 * 60 * 60 * 1_000;
const minimumCanvasWidthPixels = 840;
const yearWidthPixels = 112;
const minimumStageWidthPixels = 54;
const eventWidthPixels = 126;
const eventLeadingOffsetPixels = 6;
const endAlignedEventThresholdPercent = 90;

export function createTimelineLayout(
  items: TimelineLayoutSource[],
  referenceDate = new Date(),
  birthDate: string | null = null,
): TimelineLayout {
  const validReference = validTime(referenceDate.toISOString()) ?? Date.now();
  const birthTime = validTime(birthDate);
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

  if (normalized.length > 0 || birthTime !== null) {
    earliest = birthTime ?? Math.min(...normalized.map((item) => item.start));
    latest = Math.max(validReference, ...normalized.map((item) => item.end));
    const rawRange = Math.max(latest - earliest, minimumRangeMilliseconds);
    const padding = Math.max(rawRange * 0.025, 30 * 24 * 60 * 60 * 1_000);
    if (birthTime === null) earliest -= padding;
    latest += padding;

    if (latest - earliest < minimumRangeMilliseconds) {
      const difference = minimumRangeMilliseconds - (latest - earliest);
      if (birthTime === null) earliest -= difference / 2;
      latest += difference / 2;
    }
  }

  const range = latest - earliest;
  const yearMarkers: TimelineYearMarker[] = [];
  const firstYear = new Date(earliest).getUTCFullYear();
  const lastYear = new Date(latest).getUTCFullYear();

  if (birthTime !== null) {
    yearMarkers.push({
      label: String(firstYear),
      leftPercent: 0,
      year: firstYear,
    });
  }

  for (
    let year = birthTime === null ? firstYear : firstYear + 1;
    year <= lastYear;
    year += 1
  ) {
    const position = Date.UTC(year, 0, 1);

    if (position >= earliest && position <= latest) {
      yearMarkers.push({
        label: String(year),
        leftPercent: clamp(((position - earliest) / range) * 100),
        year,
      });
    }
  }

  const canvasWidth = Math.max(
    minimumCanvasWidthPixels,
    yearMarkers.length * yearWidthPixels,
  );
  const positions: TimelinePosition[] = [];
  const laneCountByTrack: Record<string, number> = {};
  const renderedItems = normalized.map((item) => {
    const leftPercent = clamp(((item.start - earliest) / range) * 100);
    const widthPercent =
      item.kind === "event"
        ? 0
        : clamp(((item.end - item.start) / range) * 100);
    const anchor = (leftPercent / 100) * canvasWidth;
    const widthPixels = (widthPercent / 100) * canvasWidth;
    const stageLabelOffsetPixels =
      item.kind === "stage" && item.occurredEnd === null
        ? Math.min(0, widthPixels - minimumStageWidthPixels)
        : 0;
    const visualStart =
      item.kind === "event"
        ? Math.max(
            0,
            anchor -
              (leftPercent > endAlignedEventThresholdPercent
                ? eventWidthPixels
                : eventLeadingOffsetPixels),
          )
        : anchor + stageLabelOffsetPixels;
    const visualEnd =
      item.kind === "event"
        ? Math.min(
            canvasWidth,
            anchor +
              (leftPercent > endAlignedEventThresholdPercent
                ? 0
                : eventWidthPixels - eventLeadingOffsetPixels),
          )
        : Math.min(
            canvasWidth,
            anchor +
              stageLabelOffsetPixels +
              Math.max(widthPixels, minimumStageWidthPixels),
          );

    return {
      ...item,
      leftPercent,
      stageLabelOffsetPixels,
      visualEnd,
      visualStart,
      widthPixels,
      widthPercent,
    };
  });
  const itemsByTrack = new Map<string, typeof renderedItems>();

  for (const item of renderedItems) {
    const trackItems = itemsByTrack.get(item.trackId) ?? [];
    trackItems.push(item);
    itemsByTrack.set(item.trackId, trackItems);
  }

  for (const [trackId, trackItems] of itemsByTrack) {
    const laneEnds: number[] = [];

    trackItems.sort(
      (a, b) =>
        a.visualStart - b.visualStart ||
        a.visualEnd - b.visualEnd ||
        a.start - b.start,
    );

    for (const item of trackItems) {
      let lane = laneEnds.findIndex((laneEnd) => laneEnd <= item.visualStart);

      if (lane === -1) {
        lane = laneEnds.length;
      }

      laneEnds[lane] = item.visualEnd;
      positions.push({
        id: item.id,
        lane,
        leftPercent: item.leftPercent,
        stageLabelOffsetPixels: item.stageLabelOffsetPixels,
        widthPixels: item.widthPixels,
        widthPercent: item.widthPercent,
      });
    }

    laneCountByTrack[trackId] = Math.max(1, laneEnds.length);
  }

  return {
    canvasWidth,
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
