"use server";

import { revalidatePath } from "next/cache";
import { cookies } from "next/headers";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import {
  parseBirthDate,
  parsePreferredName,
  parseProfileTimezone,
} from "@/lib/data/profile-input";
import {
  storedThemePreference,
  THEME_COOKIE_NAME,
  type ThemePreference,
} from "@/lib/theme";

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

export type PreferredNameActionResult = {
  message: string;
  preferredName?: string | null;
  status: "error" | "saved";
};

export type SemanticSearchActionResult = {
  enabled?: boolean;
  message: string;
  status: "error" | "saved";
};

export async function saveSemanticSearchPreference(
  enabled: boolean,
): Promise<SemanticSearchActionResult> {
  if (typeof enabled !== "boolean") {
    return { message: "Choose on or off.", status: "error" };
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
    .update({ semantic_search_enabled: enabled })
    .eq("user_id", context.userId)
    .select("semantic_search_enabled")
    .single();

  if (error || data?.semantic_search_enabled !== enabled) {
    return {
      message: "MemoTrail could not save Search by meaning. Try again.",
      status: "error",
    };
  }

  revalidatePath("/library");
  revalidatePath("/settings");
  return {
    enabled,
    message: enabled
      ? "Search by meaning is on."
      : "Search by meaning is off, and its index is deleted.",
    status: "saved",
  };
}

export async function savePreferredName(
  value: string,
): Promise<PreferredNameActionResult> {
  const parsed = parsePreferredName(value);
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
    .update({ display_name: parsed.preferredName })
    .eq("user_id", context.userId)
    .select("display_name")
    .single();

  if (error || data?.display_name !== parsed.preferredName) {
    return {
      message: "MemoTrail could not save your preferred name. Try again.",
      status: "error",
    };
  }

  revalidatePath("/");
  revalidatePath("/settings");
  return {
    message: parsed.preferredName
      ? "Preferred name saved."
      : "Preferred name cleared.",
    preferredName: parsed.preferredName,
    status: "saved",
  };
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
