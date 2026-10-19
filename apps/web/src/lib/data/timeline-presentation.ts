import {
  occurrenceDurationLabel,
  occurrenceLabel,
  occurrenceSpanLabel,
} from "@/lib/data/occurrence";
import type { TimelineItem } from "@/lib/data/timeline";

/** A Chapter reads as a span ("Since Mar 2021"); a First Time reads as its date. */
export function timelineItemDateLabel(item: TimelineItem) {
  return item.isChapter
    ? occurrenceSpanLabel(item.occurrence)
    : occurrenceLabel(item.occurrence);
}

/** How long a Chapter lasts, or null when it has no calendar date to measure from. */
export function timelineItemDurationLabel(item: TimelineItem, now: Date) {
  return item.isChapter && item.windowStart
    ? occurrenceDurationLabel(item.occurrence, now)
    : null;
}

/** What an item without a calendar date says about when it was. */
export function timelineUndatedLabel(item: TimelineItem) {
  const description = item.occurrence.occurredLabel?.trim();
  return description ? `Roughly: ${description}` : "Undated";
}

/** The name a bar or point carries for assistive technology. */
export function timelineItemAccessibleName(item: TimelineItem) {
  return `${item.title}, ${timelineItemDateLabel(item)}`;
}

/** One year of the vertical Timeline, with where Today falls in it. */
export type TimelineYearGroup = {
  items: TimelineItem[];
  /** In the year holding today, the index of the first item on or before today. */
  todayIndex: number | null;
  year: number;
};

/**
 * Groups the dated items by the year they start, newest first and newest first inside each
 * year, as the vertical Timeline reads. The year holding today always appears, so the Today rule
 * has a place even when nothing started this year. Items without a calendar date are left out.
 */
export function timelineYearGroups(
  items: TimelineItem[],
  today: string,
): TimelineYearGroup[] {
  const todayYear = Number(today.slice(0, 4));
  const byYear = new Map<number, TimelineItem[]>([[todayYear, []]]);

  for (const item of items) {
    if (!item.windowStart) continue;
    const year = Number(item.windowStart.slice(0, 4));
    byYear.set(year, [...(byYear.get(year) ?? []), item]);
  }

  return [...byYear.entries()]
    .sort(([a], [b]) => b - a)
    .map(([year, members]) => {
      const sorted = [...members].sort(
        (a, b) =>
          b.windowStart!.localeCompare(a.windowStart!) ||
          a.title.localeCompare(b.title),
      );
      const firstPast = sorted.findIndex((item) => item.windowStart! <= today);

      return {
        items: sorted,
        todayIndex:
          year !== todayYear
            ? null
            : firstPast === -1
              ? sorted.length
              : firstPast,
        year,
      };
    });
}

/**
 * The muted line above a title on the vertical Timeline. A First Time leaves out the year its
 * group already shows, and a Chapter reads as its span. An untitled First Time is already named
 * by its date, so it has no line.
 */
export function timelineRowDateLabel(item: TimelineItem, year: number) {
  if (item.isChapter) return `${timelineChapterSpanLabel(item)} · Chapter`;
  if (item.untitled) return null;
  const occurrence = item.occurrence;
  // The list reads by day, so an exact moment leaves out its time.
  const label = occurrenceLabel(
    occurrence.datePrecision === "exact"
      ? { ...occurrence, datePrecision: "day" }
      : occurrence,
  );
  return occurrence.occurredLabel
    ? label
    : label.replace(new RegExp(`,? ${year}\\b`, "g"), "");
}

/**
 * A Chapter's span by month, as "Sep 2026 to Oct 2026" or "Jan 2026 to now". A Chapter
 * recorded only by year reads by year.
 */
export function timelineChapterSpanLabel(item: TimelineItem) {
  const occurrence = item.occurrence;
  if (occurrence.occurredLabel || !occurrence.occurredAt) {
    return occurrenceLabel(occurrence);
  }
  const point = {
    ...occurrence,
    datePrecision:
      occurrence.datePrecision === "year"
        ? ("year" as const)
        : ("month" as const),
    occurredEnd: null,
  };
  const start = occurrenceLabel(point);
  return occurrence.occurredEnd
    ? `${start} to ${occurrenceLabel({ ...point, occurredAt: occurrence.occurredEnd })}`
    : `${start} to now`;
}

/** Today's calendar date, as YYYY-MM-DD, in the owner's time zone. */
export function timelineToday(reference: Date, timezone: string) {
  try {
    return new Intl.DateTimeFormat("en-CA", {
      day: "2-digit",
      month: "2-digit",
      timeZone: timezone,
      year: "numeric",
    }).format(reference);
  } catch {
    return reference.toISOString().slice(0, 10);
  }
}
