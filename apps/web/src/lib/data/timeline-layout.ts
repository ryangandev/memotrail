export type TimelineLayoutSource = {
  id: string;
  lane: string;
  occurredEnd: string | null;
  occurredStart: string | null;
  shape: "moment" | "period";
};

// Overlapping items in one lane stack on separate rows.
export type TimelinePosition = {
  id: string;
  leftPercent: number;
  row: number;
  periodLabelOffsetPixels: number;
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
  positions: TimelinePosition[];
  rowCountByLane: Record<string, number>;
  start: string;
  todayPercent: number;
  yearMarkers: TimelineYearMarker[];
};

const minimumRangeMilliseconds = 365 * 24 * 60 * 60 * 1_000;
const minimumCanvasWidthPixels = 840;
const yearWidthPixels = 112;
const minimumPeriodWidthPixels = 54;
const momentWidthPixels = 126;
const momentLeadingOffsetPixels = 6;
const endAlignedMomentThresholdPercent = 90;

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
        item.shape === "period"
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
  const rowCountByLane: Record<string, number> = {};
  const renderedItems = normalized.map((item) => {
    const leftPercent = clamp(((item.start - earliest) / range) * 100);
    const widthPercent =
      item.shape === "moment"
        ? 0
        : clamp(((item.end - item.start) / range) * 100);
    const anchor = (leftPercent / 100) * canvasWidth;
    const widthPixels = (widthPercent / 100) * canvasWidth;
    const periodLabelOffsetPixels =
      item.shape === "period" && item.occurredEnd === null
        ? Math.min(0, widthPixels - minimumPeriodWidthPixels)
        : 0;
    const visualStart =
      item.shape === "moment"
        ? Math.max(
            0,
            anchor -
              (leftPercent > endAlignedMomentThresholdPercent
                ? momentWidthPixels - momentLeadingOffsetPixels
                : momentLeadingOffsetPixels),
          )
        : anchor + periodLabelOffsetPixels;
    const visualEnd =
      item.shape === "moment"
        ? Math.min(
            canvasWidth,
            anchor +
              (leftPercent > endAlignedMomentThresholdPercent
                ? momentLeadingOffsetPixels
                : momentWidthPixels - momentLeadingOffsetPixels),
          )
        : Math.min(
            canvasWidth,
            anchor +
              periodLabelOffsetPixels +
              Math.max(widthPixels, minimumPeriodWidthPixels),
          );

    return {
      ...item,
      leftPercent,
      periodLabelOffsetPixels,
      visualEnd,
      visualStart,
      widthPixels,
      widthPercent,
    };
  });
  const itemsByLane = new Map<string, typeof renderedItems>();

  for (const item of renderedItems) {
    const laneItems = itemsByLane.get(item.lane) ?? [];
    laneItems.push(item);
    itemsByLane.set(item.lane, laneItems);
  }

  for (const [lane, laneItems] of itemsByLane) {
    const rowEnds: number[] = [];

    laneItems.sort(
      (a, b) =>
        a.visualStart - b.visualStart ||
        a.visualEnd - b.visualEnd ||
        a.start - b.start,
    );

    for (const item of laneItems) {
      let row = rowEnds.findIndex((rowEnd) => rowEnd <= item.visualStart);

      if (row === -1) {
        row = rowEnds.length;
      }

      rowEnds[row] = item.visualEnd;
      positions.push({
        id: item.id,
        leftPercent: item.leftPercent,
        row,
        periodLabelOffsetPixels: item.periodLabelOffsetPixels,
        widthPixels: item.widthPixels,
        widthPercent: item.widthPercent,
      });
    }

    rowCountByLane[lane] = Math.max(1, rowEnds.length);
  }

  return {
    canvasWidth,
    end: new Date(latest).toISOString(),
    positions,
    rowCountByLane,
    start: new Date(earliest).toISOString(),
    todayPercent: clamp(((validReference - earliest) / range) * 100),
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
