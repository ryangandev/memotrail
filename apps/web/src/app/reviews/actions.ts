"use server";

import { revalidatePath } from "next/cache";
import { after } from "next/server";
import { aiFeatureAvailable } from "@/lib/ai/availability";
import { runChapterSuggestions } from "@/lib/ai/chapter-suggestions";
import { REVIEW_DISCLOSURE_VERSION } from "@/lib/ai/review-disclosure";
import { aiProviderConfigured } from "@/lib/ai/server";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import {
  parseReviewSettings,
  type ReviewSettings,
} from "@/lib/data/review-input";
import { reviewToday } from "@/lib/data/reviews";

export type ReviewPreferencesResult =
  | { status: "saved"; settings: ReviewSettings; message: string }
  | { status: "stale" | "error"; message: string };

const EXPIRED = "Your session expired. Sign in again before saving.";

/**
 * Saves the two review switches. Accepting the disclosure records the version this server
 * shows, never a version sent by the browser.
 */
export async function saveReviewPreferences(input: {
  reviews: boolean;
  suggestions: boolean;
  acceptDisclosure: boolean;
  revision: number;
}): Promise<ReviewPreferencesResult> {
  if (
    typeof input?.reviews !== "boolean" ||
    typeof input.suggestions !== "boolean" ||
    typeof input.acceptDisclosure !== "boolean" ||
    !Number.isInteger(input.revision) ||
    input.revision < 0
  )
    return { status: "error", message: "Choose on or off." };

  const context = await getAuthenticatedContext();
  if (!context) return { status: "error", message: EXPIRED };

  const { data, error } = await context.client.rpc("save_review_preferences", {
    p_reviews: input.reviews,
    p_suggestions: input.suggestions,
    p_disclosure_version: input.acceptDisclosure
      ? REVIEW_DISCLOSURE_VERSION
      : null,
    p_expected_revision: input.revision,
  });
  if (error)
    return {
      status: "error",
      message:
        error.message === "review_consent_required"
          ? "Review what is sent before turning this on."
          : "MemoTrail could not save this setting. Try again.",
    };
  if (data === null)
    return {
      status: "stale",
      message:
        "Settings changed on another device. Reload before saving again.",
    };
  const settings = parseReviewSettings(data);
  if (!settings)
    return {
      status: "error",
      message: "MemoTrail could not save this setting. Try again.",
    };

  if (
    settings.chapterSuggestionsEnabled &&
    aiFeatureAvailable("chapter_suggestion") &&
    aiProviderConfigured()
  ) {
    const { localDate } = await reviewToday();
    const { client, userId } = context;
    after(() =>
      runChapterSuggestions(client, userId, localDate).then(
        () => undefined,
        () => undefined,
      ),
    );
  }

  revalidatePath("/settings");
  revalidatePath("/timeline");
  return {
    status: "saved",
    settings,
    message: input.reviews ? "Reviews are on." : "Reviews are off.",
  };
}

export async function confirmChapterSuggestion(
  id: string,
  chapterId: string,
): Promise<boolean> {
  if (typeof id !== "string" || typeof chapterId !== "string") return false;
  const context = await getAuthenticatedContext();
  if (!context) return false;
  const { data, error } = await context.client.rpc(
    "confirm_chapter_suggestion",
    {
      p_id: id,
      p_chapter_id: chapterId,
    },
  );
  revalidatePath("/timeline");
  return !error && data === true;
}

export async function dismissChapterSuggestion(id: string): Promise<boolean> {
  if (typeof id !== "string") return false;
  const context = await getAuthenticatedContext();
  if (!context) return false;
  const { data, error } = await context.client.rpc(
    "dismiss_chapter_suggestion",
    { p_id: id },
  );
  revalidatePath("/timeline");
  return !error && data === true;
}

export async function resolveReviewNotice(subject: string): Promise<boolean> {
  if (typeof subject !== "string") return false;
  const context = await getAuthenticatedContext();
  if (!context) return false;
  const { error } = await context.client.rpc("resolve_review_notice", {
    p_subject: subject,
  });
  revalidatePath("/");
  return !error;
}
