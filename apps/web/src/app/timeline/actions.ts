"use server";

import { revalidatePath } from "next/cache";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import {
  isTimelineEntryIdentity,
  parseTimelineEntryInput,
  type TimelineEntryInput,
} from "@/lib/data/timeline-input";

export type TimelineActionResult = {
  entryId?: string;
  revision?: number;
  message: string;
  status: "conflict" | "created" | "error" | "saved" | "trashed";
};

export async function saveTimelineEntry(
  input: TimelineEntryInput,
): Promise<TimelineActionResult> {
  const parsed = parseTimelineEntryInput(input);

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

  const { data, error } = await context.client.rpc(
    "save_timeline_entry_with_occurrence",
    {
      p_body: parsed.data.body,
      p_date_precision: parsed.data.datePrecision,
      p_entry_id: parsed.data.id,
      p_expected_revision: parsed.data.revision,
      p_occurred_end: parsed.data.occurredEnd,
      p_occurred_label: parsed.data.occurredLabel,
      p_occurred_start: parsed.data.occurredStart,
      p_occurred_timezone: parsed.data.occurredTimezone,
      p_timeline_kind: parsed.data.kind,
      p_title: parsed.data.title,
      p_track_id: parsed.data.trackId,
    },
  );

  if (error) {
    return {
      message: "MemoTrail could not save this moment. Try again.",
      status: "error",
    };
  }

  if (!Array.isArray(data) || data.length === 0) {
    return {
      message: parsed.data.id
        ? "This moment changed on another device. Close it, refresh, and try again."
        : "This Timeline track is no longer available. Refresh and try again.",
      status: "conflict",
    };
  }

  refreshTimelinePaths();

  return parsed.data.id
    ? {
        message: "Timeline moment saved.",
        status: "saved",
        entryId: data[0].entry_id,
        revision: data[0].revision,
      }
    : {
        message: "Added to your Timeline.",
        status: "created",
        entryId: data[0].entry_id,
        revision: data[0].revision,
      };
}

export async function trashTimelineEntry(input: {
  id: string;
  revision: number;
}): Promise<TimelineActionResult> {
  if (!isTimelineEntryIdentity(input.id, input.revision)) {
    return {
      message: "This Timeline version is invalid. Refresh and try again.",
      status: "error",
    };
  }

  const context = await getAuthenticatedContext();

  if (!context) {
    return {
      message: "Your session expired. Sign in again before continuing.",
      status: "error",
    };
  }

  const { data, error } = await context.client.rpc("trash_timeline_entry", {
    p_entry_id: input.id,
    p_expected_revision: input.revision,
  });

  if (error) {
    return {
      message: "MemoTrail could not move this moment to Trash. Try again.",
      status: "error",
    };
  }

  if (!Array.isArray(data) || data.length === 0) {
    return {
      message:
        "This moment changed on another device. Close it, refresh, and try again.",
      status: "conflict",
    };
  }

  refreshTimelinePaths();

  return { message: "Moved to Trash.", status: "trashed" };
}

function refreshTimelinePaths() {
  revalidatePath("/timeline");
  revalidatePath("/search");
}
