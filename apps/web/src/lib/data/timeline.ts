import "server-only";

import { getAuthenticatedContext, type Viewer } from "@/lib/data/inbox";
import { loadTagOptions } from "@/lib/data/tag-options";
import {
  storedBirthDate,
  storedProfileTimezone,
} from "@/lib/data/profile-input";
import {
  entryDisplayTitle,
  storedOccurrence,
  type Occurrence,
} from "@/lib/data/occurrence";

/** A Chapter or a First Time, with the whole days it covers. */
export type TimelineItem = {
  id: string;
  isChapter: boolean;
  isFirstTime: boolean;
  occurrence: Occurrence;
  revision: number;
  tagNames: string[];
  /** Its title, or its date when it has none. */
  title: string;
  updatedAt: string;
  /** The day after the last day it covers, as YYYY-MM-DD. Null while it is still going on. */
  windowEnd: string | null;
  /** The first day it covers, as YYYY-MM-DD. Null when it has no calendar date. */
  windowStart: string | null;
};

export type TimelineWorkspace = {
  birthDate: string | null;
  birthDateAvailable: boolean;
  /** Every Chapter, including the ones that are also First Times. */
  chapters: TimelineItem[];
  defaultTimezone: string;
  /** First Times that are not Chapters. */
  firstTimes: TimelineItem[];
  loadError: string | null;
  tagOptions: string[];
  viewer: Viewer;
};

export type TimelineRow = {
  date_precision: string;
  entry_id: string;
  is_chapter: boolean;
  is_first_time: boolean;
  occurred_end: string | null;
  occurred_label: string | null;
  occurred_start: string | null;
  occurred_timezone: string;
  revision: number;
  tag_names: string[];
  /** The stored title, blank when the Entry has none. */
  title: string;
  updated_at: string;
  window_end: string | null;
  window_start: string | null;
};

export async function getTimelineWorkspace(): Promise<TimelineWorkspace | null> {
  const context = await getAuthenticatedContext();

  if (!context) {
    return null;
  }

  const [timeline, profile, tags] = await Promise.all([
    context.client.rpc("timeline_workspace"),
    context.client
      .from("profiles")
      .select("*")
      .eq("user_id", context.userId)
      .single(),
    loadTagOptions(context.client, context.userId),
  ]);
  const rows = timeline.error ? null : timelineRows(timeline.data);
  const profileBirthDate = storedBirthDate(profile.error ? null : profile.data);
  const profileTimezone = storedProfileTimezone(
    profile.error ? null : profile.data,
  );
  const items = timelineItems(rows ?? []);

  return {
    birthDate: profileBirthDate.birthDate,
    birthDateAvailable: profileBirthDate.available,
    chapters: items.chapters,
    defaultTimezone: profileTimezone.timezone,
    firstTimes: items.firstTimes,
    loadError: rows
      ? null
      : "MemoTrail could not load your Timeline. Refresh to try again.",
    tagOptions: tags ?? [],
    viewer: context.viewer,
  };
}

/**
 * Splits the rows into Chapters and the First Times that are not Chapters, each by start date.
 * A First Time Chapter is one bar, so it appears in `chapters` only. Items without a calendar
 * date come last, in title order.
 */
export function timelineItems(rows: TimelineRow[]) {
  const items = rows
    .map(timelineItemFromRow)
    .sort(
      (a, b) =>
        (a.windowStart ?? "9999-99-99").localeCompare(
          b.windowStart ?? "9999-99-99",
        ) || a.title.localeCompare(b.title),
    );
  return {
    chapters: items.filter((item) => item.isChapter),
    firstTimes: items.filter((item) => item.isFirstTime && !item.isChapter),
  };
}

function timelineItemFromRow(row: TimelineRow): TimelineItem {
  const occurrence = storedOccurrence({
    datePrecision: row.date_precision,
    occurredEnd: row.occurred_end,
    occurredLabel: row.occurred_label,
    occurredStart: row.occurred_start,
    occurredTimezone: row.occurred_timezone,
  });
  return {
    id: row.entry_id,
    isChapter: row.is_chapter,
    isFirstTime: row.is_first_time,
    occurrence,
    revision: row.revision,
    tagNames: row.tag_names,
    title: entryDisplayTitle(row.title, occurrence),
    updatedAt: row.updated_at,
    windowEnd: row.window_end,
    windowStart: row.window_start,
  };
}

export function timelineRows(value: unknown): TimelineRow[] | null {
  if (!Array.isArray(value)) {
    return null;
  }

  return value.every(isTimelineRow) ? value : null;
}

const dateOnly = /^\d{4}-\d{2}-\d{2}$/;

function isTimelineRow(value: unknown): value is TimelineRow {
  if (!isRecord(value)) {
    return false;
  }

  return (
    typeof value.entry_id === "string" &&
    typeof value.title === "string" &&
    typeof value.is_chapter === "boolean" &&
    typeof value.is_first_time === "boolean" &&
    nullableString(value.occurred_start) &&
    nullableString(value.occurred_end) &&
    nullableString(value.occurred_label) &&
    typeof value.occurred_timezone === "string" &&
    typeof value.date_precision === "string" &&
    nullableDate(value.window_start) &&
    nullableDate(value.window_end) &&
    stringArray(value.tag_names) &&
    typeof value.revision === "number" &&
    typeof value.updated_at === "string"
  );
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function nullableString(value: unknown) {
  return value === null || typeof value === "string";
}

function nullableDate(value: unknown) {
  return value === null || (typeof value === "string" && dateOnly.test(value));
}

function stringArray(value: unknown): value is string[] {
  return (
    Array.isArray(value) && value.every((item) => typeof item === "string")
  );
}
