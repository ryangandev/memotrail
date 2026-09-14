"use server";

import { revalidatePath } from "next/cache";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import { parseBirthDate, parseProfileTimezone } from "@/lib/data/profile-input";

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
