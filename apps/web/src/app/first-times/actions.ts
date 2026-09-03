"use server";

import { revalidatePath } from "next/cache";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import {
  isFirstTimeEntryIdentity,
  isFirstTimeUuid,
  parseFirstTimeAttachmentInput,
  parseFirstTimeEntryInput,
  type FirstTimeAttachmentInput,
  type FirstTimeEntryInput,
} from "@/lib/data/first-time-input";

export type FirstTimeActionResult = {
  entry: { id: string; revision: number } | null;
  message: string;
  status: "conflict" | "created" | "error" | "saved" | "trashed";
};

export async function saveFirstTimeEntry(
  input: FirstTimeEntryInput,
): Promise<FirstTimeActionResult> {
  const parsed = parseFirstTimeEntryInput(input);

  if (!parsed.success) {
    return result("error", parsed.message);
  }

  const context = await getAuthenticatedContext();

  if (!context) {
    return result(
      "error",
      "Your session expired. Sign in again before saving.",
    );
  }

  const { data, error } = await context.client.rpc("save_first_time_entry", {
    p_body: parsed.data.body,
    p_collection_names: parsed.data.collectionNames,
    p_date_precision: parsed.data.datePrecision,
    p_entry_id: parsed.data.id,
    p_expected_revision: parsed.data.revision,
    p_occurred_label: parsed.data.occurredLabel,
    p_occurred_start: parsed.data.occurredStart,
    p_occurred_timezone: parsed.data.occurredTimezone,
    p_tag_names: parsed.data.tagNames,
    p_title: parsed.data.title,
  });

  if (error) {
    return result(
      "error",
      "MemoTrail could not save this First Time. Try again.",
    );
  }

  const saved = savedEntry(data);

  if (!saved) {
    return result(
      "conflict",
      parsed.data.id
        ? "This First Time changed on another device. Close it, refresh, and try again."
        : "MemoTrail could not create this First Time. Refresh and try again.",
    );
  }

  refreshFirstTimePaths();

  return {
    entry: saved,
    message: parsed.data.id ? "First Time saved." : "First Time added.",
    status: parsed.data.id ? "saved" : "created",
  };
}

export async function registerFirstTimeAttachment(
  input: FirstTimeAttachmentInput,
): Promise<FirstTimeActionResult> {
  const parsed = parseFirstTimeAttachmentInput(input);

  if (!parsed.success) {
    return result("error", parsed.message);
  }

  const context = await getAuthenticatedContext();

  if (!context) {
    return result(
      "error",
      "Your session expired before the photo could be attached.",
    );
  }

  const { data, error } = await context.client.rpc(
    "register_first_time_attachment",
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

  refreshFirstTimePaths();
  return result("saved", "Photo attached.");
}

export async function trashFirstTimeAttachment(input: {
  attachmentId: string;
}): Promise<FirstTimeActionResult> {
  if (!isFirstTimeUuid(input.attachmentId)) {
    return result(
      "error",
      "This photo reference is invalid. Refresh and try again.",
    );
  }

  const context = await getAuthenticatedContext();

  if (!context) {
    return result(
      "error",
      "Your session expired. Sign in again before continuing.",
    );
  }

  const { data, error } = await context.client.rpc(
    "trash_first_time_attachment",
    { p_attachment_id: input.attachmentId },
  );

  if (error) {
    return result("error", "MemoTrail could not remove this photo. Try again.");
  }

  if (!Array.isArray(data) || data.length === 0) {
    return result(
      "conflict",
      "This photo is no longer available. Refresh and try again.",
    );
  }

  refreshFirstTimePaths();
  return result("trashed", "Photo moved to Trash.");
}

export async function trashFirstTimeEntry(input: {
  id: string;
  revision: number;
}): Promise<FirstTimeActionResult> {
  if (!isFirstTimeEntryIdentity(input.id, input.revision)) {
    return result(
      "error",
      "This First Time version is invalid. Refresh and try again.",
    );
  }

  const context = await getAuthenticatedContext();

  if (!context) {
    return result(
      "error",
      "Your session expired. Sign in again before continuing.",
    );
  }

  const { data, error } = await context.client.rpc("trash_first_time_entry", {
    p_entry_id: input.id,
    p_expected_revision: input.revision,
  });

  if (error) {
    return result(
      "error",
      "MemoTrail could not move this First Time to Trash. Try again.",
    );
  }

  if (!Array.isArray(data) || data.length === 0) {
    return result(
      "conflict",
      "This First Time changed on another device. Close it, refresh, and try again.",
    );
  }

  refreshFirstTimePaths();
  return result("trashed", "First Time moved to Trash.");
}

function savedEntry(value: unknown) {
  if (!Array.isArray(value) || value.length === 0) {
    return null;
  }

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

function result(
  status: FirstTimeActionResult["status"],
  message: string,
): FirstTimeActionResult {
  return { entry: null, message, status };
}

function refreshFirstTimePaths() {
  revalidatePath("/");
  revalidatePath("/first-times");
  revalidatePath("/search");
  revalidatePath("/timeline");
}
