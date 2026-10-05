export type TimelineLayoutSource = {
  id: string;
  // The title's rendered width at the lane item font.
  labelWidthPixels: number;
  lane: string;
  occurredEnd: string | null;
  occurredStart: string | null;
  shape: "moment" | "period";
};

// Where a title sits: inside a Period wide enough to hold it, or beside a Moment's dot or a
// short Period's bar, before it only when it would run past the end of the Timeline.
export type TimelineLabelPlacement = "after" | "before" | "inside";

// Overlapping items in one lane stack on separate rows. An item is drawn from its anchor at
// leftPercent, shifted by offsetPixels, and is widthPixels wide including any outside label.
export type TimelinePosition = {
  barWidthPixels: number;
  id: string;
  labelPlacement: TimelineLabelPlacement;
  labelWidthPixels: number;
  leftPercent: number;
  offsetPixels: number;
  row: number;
  widthPixels: number;
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
// A Period's title sits inside when the bar holds it with its padding and borders.
const periodLabelInsetPixels = 22;
const minimumPeriodBarPixels = 10;
const momentDotPixels = 12;
const outsideLabelGapPixels = 7;
// Longer titles beside a dot or bar end in an ellipsis and show in full on hover.
const maximumOutsideLabelPixels = 180;

export function estimateLabelWidth(text: string) {
  return Math.ceil(text.length * 6.2);
}

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
    const anchor = (leftPercent / 100) * canvasWidth;
    const spanPixels =
      item.shape === "moment"
        ? 0
        : (clamp(((item.end - item.start) / range) * 100) / 100) * canvasWidth;

    if (
      item.shape === "period" &&
      spanPixels >= item.labelWidthPixels + periodLabelInsetPixels
    ) {
      return {
        ...item,
        barWidthPixels: spanPixels,
        labelPlacement: "inside" as const,
        labelWidthPixels: item.labelWidthPixels,
        leftPercent,
        offsetPixels: 0,
        visualEnd: anchor + spanPixels,
        visualStart: anchor,
        widthPixels: spanPixels,
      };
    }

    // A Moment's dot centers on its date. A short Period's bar covers its dates, and an
    // ongoing one still ends at today.
    const barWidthPixels =
      item.shape === "moment"
        ? momentDotPixels
        : Math.max(spanPixels, minimumPeriodBarPixels);
    const barStart =
      item.shape === "moment"
        ? anchor - momentDotPixels / 2
        : item.occurredEnd === null
          ? anchor + spanPixels - barWidthPixels
          : anchor;
    const barEnd = barStart + barWidthPixels;
    const labelWidthPixels = Math.min(
      item.labelWidthPixels,
      maximumOutsideLabelPixels,
    );
    const outsideWidth = outsideLabelGapPixels + labelWidthPixels;
    const labelPlacement =
      barEnd + outsideWidth <= canvasWidth
        ? ("after" as const)
        : ("before" as const);
    const visualStart =
      labelPlacement === "after" ? barStart : barStart - outsideWidth;
    const visualEnd =
      labelPlacement === "after" ? barEnd + outsideWidth : barEnd;

    return {
      ...item,
      barWidthPixels,
      labelPlacement,
      labelWidthPixels,
      leftPercent,
      offsetPixels: visualStart - anchor,
      visualEnd,
      visualStart,
      widthPixels: visualEnd - visualStart,
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
        barWidthPixels: item.barWidthPixels,
        id: item.id,
        labelPlacement: item.labelPlacement,
        labelWidthPixels: item.labelWidthPixels,
        leftPercent: item.leftPercent,
        offsetPixels: item.offsetPixels,
        row,
        widthPixels: item.widthPixels,
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
