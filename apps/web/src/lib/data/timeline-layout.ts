export type TimelineBand = "chapters" | "first-times";

// A Chapter is a bar from its window start to its window end, and a First Time is a point. The
// window is the whole days the item covers, read in its own time zone: the start is the first
// day and the end is the day after the last, or null while the stretch is still going on.
export type TimelineLayoutSource = {
  band: TimelineBand;
  id: string;
  // The title's rendered width at the band item font.
  labelWidthPixels: number;
  shape: "bar" | "point";
  // An exclusive YYYY-MM-DD date. A bar with none runs to the reference date.
  windowEnd: string | null;
  // A YYYY-MM-DD date. Items without a calendar date never reach the layout.
  windowStart: string;
};

// Where a title sits: inside a bar wide enough to hold it, or beside a point's dot or a short
// bar, before it only when it would run past the end of the Timeline.
export type TimelineLabelPlacement = "after" | "before" | "inside";

// Overlapping items in one band stack on separate rows. An item is drawn from its anchor at
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

// A month start between the year markers, drawn only when the Timeline is zoomed to months.
export type TimelineMonthMarker = {
  label: string;
  leftPercent: number;
  // 1 for January through 12 for December.
  month: number;
  year: number;
};

// Years fits a life into the visible width with at least 112 px a year; months gives every
// month 60 px.
export type TimelineZoom = "years" | "months";

export type TimelineLayout = {
  canvasWidth: number;
  end: string;
  // Empty when zoomed to years.
  monthMarkers: TimelineMonthMarker[];
  positions: TimelinePosition[];
  rowCountByBand: Record<string, number>;
  start: string;
  todayPercent: number;
  yearMarkers: TimelineYearMarker[];
};

const minimumRangeMilliseconds = 365 * 24 * 60 * 60 * 1_000;
const minimumCanvasWidthPixels = 840;
const yearWidthPixels = 112;
const monthWidthPixels = 60;
const dayMilliseconds = 24 * 60 * 60 * 1_000;
const averageMonthMilliseconds = (365.2425 / 12) * dayMilliseconds;
// Zoomed to months, the Timeline runs at least half a year past its latest date, so today can
// sit in the right third of the view with the months ahead still drawn.
const monthsTrailingMilliseconds = 183 * dayMilliseconds;
// A month start this close to the birth date's year marker would print over it.
const minimumMarkerGapPixels = 48;
const monthLabels = [
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec",
] as const;
// A bar's title sits inside when the bar holds it with its padding and borders.
const barLabelInsetPixels = 22;
const minimumBarPixels = 10;
const pointDotPixels = 12;
const outsideLabelGapPixels = 7;
// Longer titles beside a dot or bar end in an ellipsis and show in full on hover.
const maximumOutsideLabelPixels = 180;

export function estimateLabelWidth(text: string) {
  return Math.ceil(text.length * 6.2);
}

// The canvas fills the visible width, given as fillWidthPixels, and grows past it to keep
// each year legible, or each month when zoomed to months.
export function createTimelineLayout(
  items: TimelineLayoutSource[],
  referenceDate = new Date(),
  birthDate: string | null = null,
  fillWidthPixels = 0,
  zoom: TimelineZoom = "years",
): TimelineLayout {
  const validReference = validTime(referenceDate.toISOString()) ?? Date.now();
  const birthTime = validTime(birthDate);
  const normalized = items
    .map((item) => {
      const start = dateTime(item.windowStart);
      const explicitEnd = item.windowEnd ? dateTime(item.windowEnd) : null;
      const end =
        item.shape === "bar"
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
    const padding = Math.max(rawRange * 0.025, 30 * dayMilliseconds);
    if (birthTime === null) earliest -= padding;
    latest +=
      zoom === "months"
        ? Math.max(padding, monthsTrailingMilliseconds)
        : padding;

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
    Math.floor(fillWidthPixels),
    yearMarkers.length * yearWidthPixels,
    zoom === "months"
      ? Math.ceil((range / averageMonthMilliseconds) * monthWidthPixels)
      : 0,
  );
  const monthMarkers: TimelineMonthMarker[] = [];

  if (zoom === "months") {
    const first = new Date(earliest);

    // Every month start after the first instant, except January, which the year marker holds.
    for (
      let index = first.getUTCFullYear() * 12 + first.getUTCMonth() + 1;
      ;
      index += 1
    ) {
      const year = Math.floor(index / 12);
      const monthIndex = index % 12;
      const position = Date.UTC(year, monthIndex, 1);

      if (position > latest) break;
      if (monthIndex === 0) continue;

      const leftPercent = clamp(((position - earliest) / range) * 100);

      if (
        birthTime !== null &&
        (leftPercent / 100) * canvasWidth < minimumMarkerGapPixels
      ) {
        continue;
      }

      monthMarkers.push({
        label: monthLabels[monthIndex]!,
        leftPercent,
        month: monthIndex + 1,
        year,
      });
    }
  }

  const positions: TimelinePosition[] = [];
  const rowCountByBand: Record<string, number> = {};
  const renderedItems = normalized.map((item) => {
    const leftPercent = clamp(((item.start - earliest) / range) * 100);
    const anchor = (leftPercent / 100) * canvasWidth;
    const spanPixels =
      item.shape === "point"
        ? 0
        : (clamp(((item.end - item.start) / range) * 100) / 100) * canvasWidth;

    if (
      item.shape === "bar" &&
      spanPixels >= item.labelWidthPixels + barLabelInsetPixels
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

    // A point's dot centers on its date. A short bar covers its dates, and an ongoing one still
    // ends at today.
    const barWidthPixels =
      item.shape === "point"
        ? pointDotPixels
        : Math.max(spanPixels, minimumBarPixels);
    const barStart =
      item.shape === "point"
        ? anchor - pointDotPixels / 2
        : item.windowEnd === null
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
  const itemsByBand = new Map<string, typeof renderedItems>();

  for (const item of renderedItems) {
    const bandItems = itemsByBand.get(item.band) ?? [];
    bandItems.push(item);
    itemsByBand.set(item.band, bandItems);
  }

  for (const [band, bandItems] of itemsByBand) {
    const rowEnds: number[] = [];

    bandItems.sort(
      (a, b) =>
        a.visualStart - b.visualStart ||
        a.visualEnd - b.visualEnd ||
        a.start - b.start,
    );

    for (const item of bandItems) {
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

    rowCountByBand[band] = Math.max(1, rowEnds.length);
  }

  return {
    canvasWidth,
    end: new Date(latest).toISOString(),
    monthMarkers,
    positions,
    rowCountByBand,
    start: new Date(earliest).toISOString(),
    todayPercent: clamp(((validReference - earliest) / range) * 100),
    yearMarkers,
  };
}

// A date placed at midnight UTC, so year markers sit on January 1 whatever the viewer's zone.
function dateTime(value: string | null) {
  const match = value ? /^(\d{4})-(\d{2})-(\d{2})$/.exec(value) : null;
  return match
    ? Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]))
    : null;
}

function validTime(value: string | null) {
  if (value === null) return null;
  const time = new Date(value).getTime();
  return Number.isNaN(time) ? null : time;
}

function clamp(value: number) {
  return Math.max(0, Math.min(100, value));
}
