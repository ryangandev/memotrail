import "server-only";

import type { SupabaseClient } from "@supabase/supabase-js";
import { cookies } from "next/headers";
import {
  homeTimezoneCookieName,
  localDateInTimezone,
  normalizeHomeTimezone,
} from "./home-input";
import {
  parseChapterSuggestion,
  parseReviewNotice,
  parseReviewPage,
  parseReviewSettings,
  parseReviewYears,
  type ChapterSuggestion,
  type ReviewEntryRef,
  type ReviewNotice,
  type ReviewPageData,
  type ReviewSettings,
  type ReviewYear,
} from "./review-input";

/** Today for the person, in the time zone their browser last reported. */
export async function reviewToday() {
  const timezone = normalizeHomeTimezone(
    (await cookies()).get(homeTimezoneCookieName)?.value,
  );
  return { localDate: localDateInTimezone(new Date(), timezone), timezone };
}

/** The review settings, or null when they cannot be read. */
export async function loadReviewSettings(
  client: SupabaseClient,
): Promise<ReviewSettings | null> {
  const { data, error } = await client.rpc("review_settings");
  return error ? null : parseReviewSettings(data);
}

export async function loadChapterReview(
  client: SupabaseClient,
  chapterId: string,
  localDate: string,
): Promise<ReviewPageData | null> {
  const { data, error } = await client.rpc("chapter_review", {
    p_chapter_id: chapterId,
    p_local_date: localDate,
  });
  return error ? null : parseReviewPage(data);
}

export async function loadYearReview(
  client: SupabaseClient,
  year: number,
  localDate: string,
): Promise<ReviewPageData | null> {
  const { data, error } = await client.rpc("year_review", {
    p_year: year,
    p_local_date: localDate,
  });
  return error ? null : parseReviewPage(data);
}

export async function loadReviewYears(
  client: SupabaseClient,
  localDate: string,
): Promise<{ years: ReviewYear[]; failed: boolean }> {
  const { data, error } = await client.rpc("review_years", {
    p_local_date: localDate,
  });
  return error
    ? { years: [], failed: true }
    : { years: parseReviewYears(data), failed: false };
}

export async function loadReviewNotice(
  client: SupabaseClient,
  localDate: string,
): Promise<ReviewNotice | null> {
  const { data, error } = await client.rpc("review_notice", {
    p_local_date: localDate,
  });
  return error ? null : parseReviewNotice(data);
}

export async function loadPendingSuggestion(
  client: SupabaseClient,
  localDate: string,
): Promise<ChapterSuggestion | null> {
  const { data, error } = await client.rpc("pending_chapter_suggestion", {
    p_local_date: localDate,
  });
  return error ? null : parseChapterSuggestion(data);
}

/** A Chapter whose review has been made, as the Reviews list shows it. */
export type ChapterReviewListing = {
  chapter: ReviewEntryRef;
  generatedAt: string;
  ongoing: boolean;
};

const PRECISIONS: readonly string[] = [
  "exact",
  "day",
  "month",
  "year",
  "approximate",
  "age",
  "range",
  "unknown",
];

const textOf = (value: unknown) => (typeof value === "string" ? value : null);

/**
 * The made Chapter reviews, newest Chapter first: a Chapter that started later comes before one
 * that started earlier, and an undated Chapter comes last. A Chapter in Trash, or one that is no
 * longer a Chapter, is left out, since its page does not show the review either.
 */
export function chapterReviewListings(rows: unknown): ChapterReviewListing[] {
  if (!Array.isArray(rows)) return [];
  const listings = rows.flatMap((row): ChapterReviewListing[] => {
    if (typeof row !== "object" || row === null) return [];
    const {
      chapter,
      generated_at: generatedAt,
      ongoing,
    } = row as Record<string, unknown>;
    if (typeof generatedAt !== "string") return [];
    if (typeof chapter !== "object" || chapter === null) return [];
    const entry = chapter as Record<string, unknown>;
    if (typeof entry.id !== "string") return [];
    if (entry.deleted_at != null || entry.item_subtype !== "chapter") return [];
    const precision = textOf(entry.date_precision) ?? "";
    return [
      {
        chapter: {
          id: entry.id,
          title: textOf(entry.title)?.trim() ?? "",
          occurredStart: textOf(entry.occurred_start),
          occurredEnd: textOf(entry.occurred_end),
          occurredLabel: textOf(entry.occurred_label),
          occurredTimezone: textOf(entry.occurred_timezone) ?? "UTC",
          datePrecision: (PRECISIONS.includes(precision)
            ? precision
            : "unknown") as ReviewEntryRef["datePrecision"],
        },
        generatedAt,
        ongoing: ongoing === true,
      },
    ];
  });
  const start = ({ chapter }: ChapterReviewListing) => {
    const time =
      chapter.datePrecision === "unknown" || !chapter.occurredStart
        ? Number.NaN
        : Date.parse(chapter.occurredStart);
    return Number.isNaN(time) ? Number.NEGATIVE_INFINITY : time;
  };
  return listings.sort((a, b) => {
    const order = start(b) - start(a);
    return order === 0 || Number.isNaN(order)
      ? Date.parse(b.generatedAt) - Date.parse(a.generatedAt)
      : order;
  });
}

export async function loadChapterReviews(
  client: SupabaseClient,
): Promise<{ chapters: ChapterReviewListing[]; failed: boolean }> {
  const { data, error } = await client
    .from("entry_reviews")
    .select(
      "generated_at,ongoing,chapter:entries(id,title,item_subtype,deleted_at,occurred_start,occurred_end,occurred_label,occurred_timezone,date_precision)",
    )
    .eq("scope", "chapter")
    .not("content", "is", null);
  return error
    ? { chapters: [], failed: true }
    : { chapters: chapterReviewListings(data), failed: false };
}
