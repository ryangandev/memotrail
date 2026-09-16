"use server";

import { revalidatePath } from "next/cache";
import { writingRevision } from "@/lib/media/writing-revision";
import {
  isFirstTimeUuid,
  parseFirstTimeAttachmentInput,
  type FirstTimeAttachmentInput,
} from "@/lib/data/first-time-input";
import {
  isGoalEntryIdentity,
  parseGoalAchievementInput,
  parseGoalEntryInput,
  type GoalAchievementInput,
  type GoalEntryInput,
} from "@/lib/data/goal-record-input";
import {
  parseCaptureExtractionReference,
  type CaptureExtractionReference,
} from "@/lib/data/capture-extraction-input";
import { getAuthenticatedContext } from "@/lib/data/inbox";

export type GoalActionResult = {
  entry: { id: string; revision: number } | null;
  firstTimeEntryId: string | null;
  message: string;
  status: "achieved" | "conflict" | "created" | "error" | "saved" | "trashed";
};

export async function saveGoalEntry(
  input: GoalEntryInput,
  sourceCapture: CaptureExtractionReference | null = null,
): Promise<GoalActionResult> {
  const parsed = parseGoalEntryInput(input);
  if (!parsed.success) return result("error", parsed.message);

  const context = await getAuthenticatedContext();
  if (!context) return expiredSession();

  const source = sourceCapture
    ? parseCaptureExtractionReference(sourceCapture)
    : null;
  if (sourceCapture && (!source || parsed.data.id !== null)) {
    return result(
      "error",
      "This Capture handoff is invalid. Return to Inbox and try again.",
    );
  }

  const parameters = {
    p_body: parsed.data.body,
    p_collection_names: parsed.data.collectionNames,
    p_horizon: parsed.data.horizon,
    p_related_entry_ids: parsed.data.relatedEntryIds,
    p_status: parsed.data.status,
    p_tag_names: parsed.data.tagNames,
    p_target_date: parsed.data.targetDate,
    p_title: parsed.data.title,
  };
  const { data, error } = source
    ? await context.client.rpc("extract_capture_to_goal", {
        ...parameters,
        p_capture_id: source.id,
        p_capture_revision: source.revision,
      })
    : await context.client.rpc("save_goal_entry", {
        ...parameters,
        p_entry_id: parsed.data.id,
        p_expected_revision: await writingRevision(
          context.client,
          parsed.data.id,
          parsed.data.revision,
        ),
      });
  if (error) {
    return result("error", "MemoTrail could not save this Goal. Try again.");
  }

  const saved = source ? extractedGoal(data) : savedGoal(data);
  if (!saved) {
    return result(
      "conflict",
      parsed.data.id
        ? "This Goal changed on another device. Close it, refresh, and try again."
        : source
          ? "This Capture changed or was already organized. Return to Inbox and refresh."
          : "MemoTrail could not create this Goal. Refresh and try again.",
    );
  }

  refreshGoalPaths();
  return {
    entry: saved,
    firstTimeEntryId: null,
    message: parsed.data.id
      ? "Goal saved."
      : source
        ? "Goal created from Capture."
        : "Goal added.",
    status: parsed.data.id ? "saved" : "created",
  };
}

export async function markGoalAchieved(
  input: GoalAchievementInput,
): Promise<GoalActionResult> {
  const parsed = parseGoalAchievementInput(input);
  if (!parsed.success) return result("error", parsed.message);

  const context = await getAuthenticatedContext();
  if (!context) return expiredSession();

  const { data, error } = await context.client.rpc(
    "achieve_goal_with_occurrence",
    {
      p_date_precision: parsed.data.datePrecision,
      p_expected_revision: parsed.data.revision,
      p_goal_entry_id: parsed.data.id,
      p_occurred_label: parsed.data.occurredLabel,
      p_occurred_start: parsed.data.occurredStart,
      p_occurred_end: parsed.data.occurredEnd ?? null,
      p_occurred_timezone: parsed.data.occurredTimezone,
    },
  );
  if (error) {
    return result(
      "error",
      "MemoTrail could not record this achievement. Try again.",
    );
  }
  const achieved = achievedGoal(data);
  if (!achieved) {
    return result(
      "conflict",
      "This Goal changed or is no longer in Bucket List. Close it, refresh, and try again.",
    );
  }

  refreshGoalPaths();
  return {
    entry: { id: achieved.id, revision: achieved.revision },
    firstTimeEntryId: achieved.firstTimeEntryId,
    message: "Achievement saved, with a linked First Time.",
    status: "achieved",
  };
}

export async function registerGoalAttachment(
  input: FirstTimeAttachmentInput,
): Promise<GoalActionResult> {
  const parsed = parseFirstTimeAttachmentInput(input);
  if (!parsed.success) return result("error", parsed.message);

  const context = await getAuthenticatedContext();
  if (!context) {
    return result(
      "error",
      "Your session expired before the photo could be attached.",
    );
  }

  const { data, error } = await context.client.rpc(
    "register_entry_attachment",
    {
      p_attachment_id: parsed.data.attachmentId,
      p_byte_size: parsed.data.byteSize,
      p_entry_id: parsed.data.entryId,
      p_mime_type: parsed.data.mimeType,
      p_object_path: parsed.data.objectPath,
      p_original_filename: parsed.data.originalFilename,
      p_pixel_height: parsed.data.pixelHeight,
      p_pixel_width: parsed.data.pixelWidth,
    },
  );
  if (error || !Array.isArray(data) || data.length === 0) {
    return result(
      "error",
      "The photo uploaded, but MemoTrail could not attach it. Try again.",
    );
  }

  refreshGoalPaths();
  return result("saved", "Photo attached.");
}

export async function trashGoalAttachment(input: {
  attachmentId: string;
}): Promise<GoalActionResult> {
  if (!isFirstTimeUuid(input.attachmentId)) {
    return result(
      "error",
      "This photo reference is invalid. Refresh and try again.",
    );
  }

  const context = await getAuthenticatedContext();
  if (!context) return expiredSession();

  const { data, error } = await context.client.rpc("trash_entry_attachment", {
    p_attachment_id: input.attachmentId,
  });
  if (error) {
    return result("error", "MemoTrail could not remove this photo. Try again.");
  }
  if (!Array.isArray(data) || data.length === 0) {
    return result(
      "conflict",
      "This photo is no longer available. Refresh and try again.",
    );
  }

  refreshGoalPaths();
  return result("trashed", "Photo moved to Trash.");
}

export async function trashGoalEntry(input: {
  id: string;
  revision: number;
}): Promise<GoalActionResult> {
  if (!isGoalEntryIdentity(input.id, input.revision)) {
    return result(
      "error",
      "This Goal version is invalid. Refresh and try again.",
    );
  }

  const context = await getAuthenticatedContext();
  if (!context) return expiredSession();

  const { data, error } = await context.client.rpc("trash_goal_entry", {
    p_entry_id: input.id,
    p_expected_revision: input.revision,
  });
  if (error) {
    return result(
      "error",
      "MemoTrail could not move this Goal to Trash. Try again.",
    );
  }
  if (!Array.isArray(data) || data.length === 0) {
    return result(
      "conflict",
      "This Goal changed on another device. Close it, refresh, and try again.",
    );
  }

  refreshGoalPaths();
  return result("trashed", "Goal moved to Trash.");
}

function savedGoal(value: unknown) {
  if (!Array.isArray(value) || value.length === 0) return null;
  const item = value[0];
  return typeof item === "object" &&
    item !== null &&
    "entry_id" in item &&
    "revision" in item &&
    typeof item.entry_id === "string" &&
    typeof item.revision === "number"
    ? { id: item.entry_id, revision: item.revision }
    : null;
}

function extractedGoal(value: unknown) {
  if (!Array.isArray(value) || value.length === 0) return null;
  const item = value[0];
  return typeof item === "object" &&
    item !== null &&
    "goal_entry_id" in item &&
    "goal_revision" in item &&
    typeof item.goal_entry_id === "string" &&
    typeof item.goal_revision === "number"
    ? { id: item.goal_entry_id, revision: item.goal_revision }
    : null;
}

function achievedGoal(value: unknown) {
  if (!Array.isArray(value) || value.length === 0) return null;
  const item = value[0];
  return typeof item === "object" &&
    item !== null &&
    "goal_entry_id" in item &&
    "goal_revision" in item &&
    "first_time_entry_id" in item &&
    typeof item.goal_entry_id === "string" &&
    typeof item.goal_revision === "number" &&
    typeof item.first_time_entry_id === "string"
    ? {
        firstTimeEntryId: item.first_time_entry_id,
        id: item.goal_entry_id,
        revision: item.goal_revision,
      }
    : null;
}

function result(
  status: GoalActionResult["status"],
  message: string,
): GoalActionResult {
  return { entry: null, firstTimeEntryId: null, message, status };
}

function expiredSession(): GoalActionResult {
  return result(
    "error",
    "Your session expired. Sign in again before continuing.",
  );
}

function refreshGoalPaths() {
  revalidatePath("/");
  revalidatePath("/collections");
  revalidatePath("/first-times");
  revalidatePath("/goals");
  revalidatePath("/inbox");
  revalidatePath("/library");
  revalidatePath("/search");
  revalidatePath("/trash");
}
