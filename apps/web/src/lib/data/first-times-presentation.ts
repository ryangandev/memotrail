import type { FirstTimeEntry } from "@/lib/data/first-times";
import { countLabel } from "@/lib/count-label";
import { locationDisplayLabel } from "@/lib/locations/location";
import {
  occurrenceLabel,
  occurrenceSpanLabel,
  storedOccurrence,
} from "@/lib/data/occurrence";

type FirstTimeRowSource = Pick<
  FirstTimeEntry,
  | "attachments"
  | "datePrecision"
  | "isChapter"
  | "location"
  | "occurredEnd"
  | "occurredLabel"
  | "occurredStart"
  | "occurredTimezone"
  | "tagNames"
  | "untitled"
>;

/**
 * The date column of a First Time row, at the precision it was recorded. A First Time that is
 * also a Chapter reads as its span. An untitled one is already named by its date, so its
 * column is empty.
 */
export function firstTimeRowDateLabel(entry: FirstTimeRowSource) {
  if (entry.untitled) return null;
  const occurrence = storedOccurrence({
    datePrecision:
      entry.datePrecision === "exact" ? "day" : entry.datePrecision,
    occurredEnd: entry.occurredEnd,
    occurredLabel: entry.occurredLabel,
    occurredStart: entry.occurredStart,
    occurredTimezone: entry.occurredTimezone,
  });
  if (
    !occurrence.occurredLabel &&
    (!occurrence.occurredAt || occurrence.datePrecision === "unknown")
  ) {
    return "Undated";
  }
  return entry.isChapter
    ? occurrenceSpanLabel(occurrence)
    : occurrenceLabel(occurrence);
}

/** The photos a First Time keeps, one per saved photo rather than per size. */
export function firstTimePhotos(entry: Pick<FirstTimeEntry, "attachments">) {
  return entry.attachments.filter(
    (attachment) => attachment.variant === "original",
  );
}

/**
 * The quiet line under a First Time's excerpt: where, by its city when it has one, how many
 * photos, and its tags.
 */
export function firstTimeRowDetails(entry: FirstTimeRowSource) {
  const photos = firstTimePhotos(entry).length;
  return [
    entry.location
      ? entry.location.city?.trim() || locationDisplayLabel(entry.location)
      : null,
    photos > 0 ? countLabel(photos, "photo") : null,
    entry.tagNames.length > 0
      ? entry.tagNames.map((name) => `#${name}`).join(" ")
      : null,
  ].filter((part): part is string => Boolean(part));
}

/** One line of a First Time's writing, with its line breaks folded into spaces. */
export function firstTimeExcerpt(body: string) {
  return body.replace(/\s+/g, " ").trim();
}
