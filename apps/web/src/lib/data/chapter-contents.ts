import "server-only";

import type { SupabaseClient } from "@supabase/supabase-js";
import { displayImageURLs } from "@/lib/media/urls";
import {
  entryDisplayTitle,
  storedOccurrence,
  type Occurrence,
} from "./occurrence";

/** How many Entries one page of a Chapter lists. */
export const chapterEntriesPageSize = 50;

export type ChapterCoverPhoto = {
  alt: string;
  /** Signed for display, or null when the photo cannot be shown. */
  imageUrl: string | null;
  objectPath: string;
};

/** An Entry dated inside a Chapter. */
export type ChapterEntry = {
  coverPhoto: ChapterCoverPhoto | null;
  excerpt: string;
  id: string;
  isFirstTime: boolean;
  occurrence: Occurrence;
  tagNames: string[];
  /** The stored title, blank when the Entry has none. */
  title: string;
};

/** A Chapter or First Time whose days overlap this Chapter's. */
export type ChapterOverlap = {
  id: string;
  isFirstTime: boolean;
  occurrence: Occurrence;
  /** Its title, or its date when it has none. */
  title: string;
};

export type ChapterContents = {
  entries: ChapterEntry[];
  /** True when the Entries could not load. */
  failed: boolean;
  overlaps: ChapterOverlap[];
  totalCount: number;
};

type ChapterEntryRow = {
  cover_photo: {
    attachment_id: string;
    bucket_id: string;
    byte_size: number | null;
    mime_type: string;
    object_path: string;
    original_filename: string | null;
    pixel_height: number | null;
    pixel_width: number | null;
  } | null;
  date_precision: string;
  entry_id: string;
  excerpt: string;
  is_first_time: boolean;
  occurred_end: string | null;
  occurred_label: string | null;
  occurred_start: string | null;
  occurred_timezone: string;
  tag_names: string[];
  title: string;
  total_count: number | string;
};

type ChapterOverlapRow = {
  date_precision: string;
  entry_id: string;
  is_first_time: boolean;
  occurred_end: string | null;
  occurred_label: string | null;
  occurred_start: string | null;
  occurred_timezone: string;
  title: string;
};

/** A page number from the address, 1 when it is missing or out of range. */
export function chapterPage(value: unknown) {
  const page = Number(Array.isArray(value) ? value[0] : (value ?? 1));
  return Number.isSafeInteger(page) && page >= 1 && page <= 2_001 ? page : 1;
}

/**
 * The Entries dated inside a Chapter, oldest first, one page of them, and the other Chapters and
 * First Times during the same days. A Chapter without a calendar date has neither.
 */
export async function loadChapterContents(
  client: SupabaseClient,
  chapterId: string,
  page: number,
): Promise<ChapterContents> {
  const [entries, overlaps] = await Promise.all([
    client.rpc("chapter_entries", {
      p_chapter_id: chapterId,
      p_limit: chapterEntriesPageSize,
      p_offset: (page - 1) * chapterEntriesPageSize,
    }),
    client.rpc("chapter_overlaps", { p_chapter_id: chapterId }),
  ]);
  const entryRows = entries.error ? null : chapterEntryRows(entries.data);
  const overlapRows = overlaps.error ? null : chapterOverlapRows(overlaps.data);

  if (!entryRows || !overlapRows) {
    return { entries: [], failed: true, overlaps: [], totalCount: 0 };
  }

  const signedUrls = await displayImageURLs(
    client,
    entryRows.flatMap((row) =>
      row.cover_photo ? [row.cover_photo.object_path] : [],
    ),
  );

  return {
    entries: entryRows.map((row) => ({
      coverPhoto: row.cover_photo
        ? {
            alt: row.cover_photo.original_filename || "Entry photo",
            imageUrl: signedUrls.get(row.cover_photo.object_path) ?? null,
            objectPath: row.cover_photo.object_path,
          }
        : null,
      excerpt: row.excerpt,
      id: row.entry_id,
      isFirstTime: row.is_first_time,
      occurrence: rowOccurrence(row),
      tagNames: row.tag_names,
      title: row.title,
    })),
    failed: false,
    overlaps: overlapRows.map((row) => ({
      id: row.entry_id,
      isFirstTime: row.is_first_time,
      occurrence: rowOccurrence(row),
      title: entryDisplayTitle(row.title, rowOccurrence(row)),
    })),
    totalCount: Number(entryRows[0]?.total_count ?? 0),
  };
}

export function chapterEntryRows(value: unknown): ChapterEntryRow[] | null {
  return Array.isArray(value) && value.every(isChapterEntryRow) ? value : null;
}

export function chapterOverlapRows(
  value: unknown,
): ChapterOverlapRow[] | null {
  return Array.isArray(value) && value.every(isChapterOverlapRow)
    ? value
    : null;
}

function rowOccurrence(row: ChapterEntryRow | ChapterOverlapRow) {
  return storedOccurrence({
    datePrecision: row.date_precision,
    occurredEnd: row.occurred_end,
    occurredLabel: row.occurred_label,
    occurredStart: row.occurred_start,
    occurredTimezone: row.occurred_timezone,
  });
}

function isChapterEntryRow(value: unknown): value is ChapterEntryRow {
  if (!isRecord(value)) return false;
  return (
    typeof value.entry_id === "string" &&
    typeof value.title === "string" &&
    typeof value.excerpt === "string" &&
    typeof value.is_first_time === "boolean" &&
    hasOccurrence(value) &&
    stringArray(value.tag_names) &&
    (value.cover_photo === null || isCoverPhoto(value.cover_photo)) &&
    Number.isFinite(Number(value.total_count))
  );
}

function isChapterOverlapRow(value: unknown): value is ChapterOverlapRow {
  if (!isRecord(value)) return false;
  return (
    typeof value.entry_id === "string" &&
    typeof value.title === "string" &&
    typeof value.is_first_time === "boolean" &&
    hasOccurrence(value)
  );
}

function hasOccurrence(value: Record<string, unknown>) {
  return (
    nullableString(value.occurred_start) &&
    nullableString(value.occurred_end) &&
    nullableString(value.occurred_label) &&
    typeof value.occurred_timezone === "string" &&
    typeof value.date_precision === "string"
  );
}

function isCoverPhoto(value: unknown) {
  return (
    isRecord(value) &&
    typeof value.attachment_id === "string" &&
    typeof value.bucket_id === "string" &&
    typeof value.object_path === "string" &&
    typeof value.mime_type === "string" &&
    nullableString(value.original_filename)
  );
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function nullableString(value: unknown) {
  return value === null || typeof value === "string";
}

function stringArray(value: unknown): value is string[] {
  return (
    Array.isArray(value) && value.every((item) => typeof item === "string")
  );
}
