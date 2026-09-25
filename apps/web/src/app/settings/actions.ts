"use server";

import { revalidatePath } from "next/cache";
import { cookies } from "next/headers";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import { parseBirthDate, parseProfileTimezone } from "@/lib/data/profile-input";
import {
  storedThemePreference,
  THEME_COOKIE_NAME,
  type ThemePreference,
} from "@/lib/theme";
import {
  parseTimelineStyle,
  TIMELINE_STYLE_COOKIE_NAME,
  timelineStyleCookieValue,
  type TimelineStyle,
} from "@/lib/timeline-style";

export type BirthDateActionResult = {
  birthDate?: string | null;
  message: string;
  status: "error" | "saved";
};

export type TimezoneActionResult = {
  message: string;
  status: "error" | "saved";
  timezone?: string;
};

export type TimelineStyleActionResult =
  | { status: "saved"; style: TimelineStyle }
  | { status: "error"; message: string };

export async function saveTimelineStyle(
  value: string,
): Promise<TimelineStyleActionResult> {
  const style = parseTimelineStyle(value);
  if (!style) {
    return { status: "error", message: "Choose a valid Timeline style." };
  }
  const context = await getAuthenticatedContext();
  if (!context) {
    return {
      status: "error",
      message: "Your session expired. Sign in again before saving.",
    };
  }
  (await cookies()).set(
    TIMELINE_STYLE_COOKIE_NAME,
    timelineStyleCookieValue(context.userId, style),
    {
      httpOnly: true,
      maxAge: 60 * 60 * 24 * 365,
      path: "/",
      sameSite: "lax",
      secure: process.env.NODE_ENV === "production",
    },
  );
  revalidatePath("/timeline");
  return { status: "saved", style };
}

export async function saveThemePreference(
  value: ThemePreference,
): Promise<ThemePreference> {
  const preference = storedThemePreference(value);
  const cookieStore = await cookies();
  cookieStore.set(THEME_COOKIE_NAME, preference, {
    httpOnly: true,
    maxAge: 60 * 60 * 24 * 365,
    path: "/",
    sameSite: "lax",
    secure: process.env.NODE_ENV === "production",
  });
  return preference;
}

export async function saveBirthDate(
  value: string,
): Promise<BirthDateActionResult> {
  const parsed = parseBirthDate(value);

  if (!parsed.success) {
    return { message: parsed.message, status: "error" };
  }

  const context = await getAuthenticatedContext();

  if (!context) {
    return {
      message: "Your session expired. Sign in again before saving.",
      status: "error",
    };
  }

  const { data, error } = await context.client
    .from("profiles")
    .update({ birth_date: parsed.birthDate })
    .eq("user_id", context.userId)
    .select("birth_date")
    .single();

  if (error || data?.birth_date !== parsed.birthDate) {
    return {
      message: "MemoTrail could not save your birth date. Try again.",
      status: "error",
    };
  }

  revalidatePath("/timeline");
  revalidatePath("/settings");

  return {
    birthDate: parsed.birthDate,
    message: parsed.birthDate ? "Birth date saved." : "Birth date removed.",
    status: "saved",
  };
}

export async function saveProfileTimezone(
  value: string,
): Promise<TimezoneActionResult> {
  const parsed = parseProfileTimezone(value);

  if (!parsed.success) {
    return { message: parsed.message, status: "error" };
  }

  const context = await getAuthenticatedContext();

  if (!context) {
    return {
      message: "Your session expired. Sign in again before saving.",
      status: "error",
    };
  }

  const { data, error } = await context.client
    .from("profiles")
    .update({ timezone: parsed.timezone })
    .eq("user_id", context.userId)
    .select("timezone")
    .single();

  if (error || data?.timezone !== parsed.timezone) {
    return {
      message: "MemoTrail could not save your default time zone. Try again.",
      status: "error",
    };
  }

  revalidatePath("/timeline");
  revalidatePath("/settings");

  return {
    message: "Default time zone saved.",
    status: "saved",
    timezone: parsed.timezone,
  };
}
