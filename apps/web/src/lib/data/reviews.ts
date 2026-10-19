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
