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
