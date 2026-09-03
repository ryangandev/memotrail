"use server";

import { revalidatePath } from "next/cache";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import {
  isHabitIdentity,
  parseHabitInput,
  parseHabitOccurrenceInput,
  type HabitInput,
  type HabitOccurrenceInput,
} from "@/lib/data/habit-input";

export type HabitActionResult = {
  message: string;
  status: "conflict" | "created" | "error" | "saved" | "trashed";
};

export async function saveHabit(input: HabitInput): Promise<HabitActionResult> {
  const parsed = parseHabitInput(input);

  if (!parsed.success) {
    return { message: parsed.message, status: "error" };
  }

  const context = await getAuthenticatedContext();

  if (!context) {
    return expiredSession();
  }

  const { data, error } = await context.client.rpc("save_habit", {
    p_ends_on: parsed.data.endsOn,
    p_expected_revision: parsed.data.revision,
    p_habit_id: parsed.data.id,
    p_measurement_unit: parsed.data.measurementUnit,
    p_name: parsed.data.name,
    p_schedule: parsed.data.schedule,
    p_starts_on: parsed.data.startsOn,
    p_target_value: parsed.data.targetValue,
    p_tracking_mode: parsed.data.trackingMode,
  });

  if (error) {
    return {
      message: "MemoTrail could not save this Habit. Try again.",
      status: "error",
    };
  }

  if (!Array.isArray(data) || data.length === 0) {
    return {
      message: parsed.data.id
        ? "This Habit changed on another device. Close it, refresh, and try again."
        : "MemoTrail could not create this Habit. Refresh and try again.",
      status: "conflict",
    };
  }

  refreshHabitPaths();
  return parsed.data.id
    ? { message: "Habit saved.", status: "saved" }
    : { message: "Habit added.", status: "created" };
}

export async function recordHabitOccurrence(
  input: HabitOccurrenceInput,
): Promise<HabitActionResult> {
  const parsed = parseHabitOccurrenceInput(input);

  if (!parsed.success) {
    return { message: parsed.message, status: "error" };
  }

  const context = await getAuthenticatedContext();

  if (!context) {
    return expiredSession();
  }

  const { data, error } = await context.client.rpc("record_habit_occurrence", {
    p_entry_id: null,
    p_expected_revision: parsed.data.expectedRevision,
    p_habit_id: parsed.data.habitId,
    p_local_date: parsed.data.localDate,
    p_measured_value: parsed.data.measuredValue,
    p_note: parsed.data.note,
    p_status: parsed.data.status,
  });

  if (error) {
    return {
      message: "MemoTrail could not save this check-in. Try again.",
      status: "error",
    };
  }

  if (!Array.isArray(data) || data.length === 0) {
    return {
      message:
        "This check-in changed on another device. Close it, refresh, and try again.",
      status: "conflict",
    };
  }

  refreshHabitPaths();
  return {
    message: parsed.data.expectedRevision
      ? "Check-in updated."
      : "Check-in saved.",
    status: "saved",
  };
}

export async function trashHabit(input: {
  id: string;
  revision: number;
}): Promise<HabitActionResult> {
  if (!isHabitIdentity(input.id, input.revision)) {
    return {
      message: "This Habit version is invalid. Refresh and try again.",
      status: "error",
    };
  }

  const context = await getAuthenticatedContext();

  if (!context) {
    return expiredSession();
  }

  const { data, error } = await context.client.rpc("trash_habit", {
    p_expected_revision: input.revision,
    p_habit_id: input.id,
  });

  if (error) {
    return {
      message: "MemoTrail could not move this Habit to Trash. Try again.",
      status: "error",
    };
  }

  if (!Array.isArray(data) || data.length === 0) {
    return {
      message:
        "This Habit changed on another device. Close it, refresh, and try again.",
      status: "conflict",
    };
  }

  refreshHabitPaths();
  return { message: "Habit moved to Trash.", status: "trashed" };
}

function expiredSession(): HabitActionResult {
  return {
    message: "Your session expired. Sign in again before saving.",
    status: "error",
  };
}

function refreshHabitPaths() {
  revalidatePath("/habits");
}
