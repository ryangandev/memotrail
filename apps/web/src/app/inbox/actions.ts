"use server";

import { revalidatePath } from "next/cache";
import { after } from "next/server";
import { AI_CAPABILITIES_AVAILABLE } from "@/lib/ai/availability";
import { suggestForEntry } from "@/lib/ai/suggestions-server";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import {
  parseFirstTimeAttachmentInput,
  type FirstTimeAttachmentInput,
} from "@/lib/data/first-time-input";
import {
  isQueuedInboxEntry,
  queuedOccurrence,
  type QueuedInboxEntry,
} from "@/lib/data/inbox-queue";
import {
  parseInboxReviewInput,
  type InboxReviewInput,
} from "@/lib/data/inbox-review";
import {
  metadataWithEntryRichText,
  parseEntryRichTextJson,
} from "@/lib/data/rich-text";
import {
  deletedForeverMessage,
  missingPhotoMessage,
  photoSessionMessage,
  rejectedEntryMessage,
  rejectedPhotoMessage,
  trashedEntryMessage,
  trashedPhotoMessage,
} from "@/lib/data/capture-sync-messages";
import { classifySyncFailure, type SyncFailure } from "@/lib/data/sync-failure";

/**
 * `retry` keeps a capture waiting for a later attempt; `rejected` means
 * MemoTrail will never accept it, so it waits for the person instead.
 */
export type SyncInboxEntryResult = {
  message: string;
  status: "rejected" | "retry" | "synced";
};

const invalidEntryMessage =
  "This Entry is invalid on this device, so it will not sync. Copy its text to keep it, then discard it.";

// MemoTrail names its own refusals in the error message, beside a standard
// SQLSTATE that deployed clients already classify.
type MemoTrailError = { code?: string | null; message?: string | null };
/** The Entry was deleted forever, so its ID can never be created again. */
const isDeletedForever = (error: MemoTrailError) =>
  error.code === "23505" && error.message === "entry_deleted_forever";
/** The Entry is in Trash, so it cannot take photos. */
const isInTrash = (error: MemoTrailError) =>
  error.code === "22023" && error.message === "entry_in_trash";
/** The original has not reached Storage. */
const isOriginalMissing = (error: MemoTrailError) =>
  error.code === "22023" && error.message === "attachment_object_missing";

export type ReviewInboxEntryResult =
  | { message: string; status: "conflict" | "error" }
  | { message: string; status: "saved"; revision: number };

/**
 * Registers an uploaded original. Pass `originalOnDevice: false` when this
 * device no longer has the photo, so an original that never reached Storage
 * is final instead of waiting for an upload that cannot happen.
 */
export async function registerEntryAttachment(
  input: FirstTimeAttachmentInput,
  options?: { originalOnDevice?: boolean },
): Promise<SyncInboxEntryResult> {
  const originalOnDevice = options?.originalOnDevice !== false;
  const parsed = parseFirstTimeAttachmentInput(input);

  if (!parsed.success) {
    return { message: rejectedPhotoMessage, status: "rejected" };
  }

  const context = await getAuthenticatedContext();

  if (!context) {
    return photoSyncFailure("session");
  }

  const { data, error, status } = await context.client.rpc(
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

  if (error) {
    if (isInTrash(error))
      return { message: trashedPhotoMessage, status: "rejected" };
    if (isDeletedForever(error))
      return { message: deletedForeverMessage, status: "rejected" };
    // Uploading the original again can still succeed while this device has it.
    if (isOriginalMissing(error))
      return originalOnDevice
        ? photoSyncFailure("unavailable")
        : { message: missingPhotoMessage, status: "rejected" };
    return photoSyncFailure(
      classifySyncFailure({ code: error.code, status }),
      originalOnDevice,
    );
  }

  if (!Array.isArray(data) || data.length === 0) {
    return photoSyncFailure("unavailable", originalOnDevice);
  }

  revalidatePath("/");
  revalidatePath("/library");
  revalidatePath("/search");

  return { message: "Photo attached.", status: "synced" };
}

export async function syncInboxEntry(
  input: QueuedInboxEntry,
  bodyRichJson: string | null = null,
): Promise<SyncInboxEntryResult> {
  if (!isQueuedInboxEntry(input)) {
    return { message: invalidEntryMessage, status: "rejected" };
  }

  const bodyRich = parseEntryRichTextJson(bodyRichJson, input.body);
  const entry: QueuedInboxEntry = { ...input, bodyRich };

  if (bodyRichJson !== null && bodyRich === null) {
    return { message: invalidEntryMessage, status: "rejected" };
  }

  const context = await getAuthenticatedContext();

  if (!context) {
    return entrySyncFailure("session");
  }

  const occurrence = queuedOccurrence(entry);
  const { error, status } = await context.client.from("entries").insert({
    body: entry.body,
    client_id: `web:${entry.id}`,
    date_precision: occurrence.datePrecision,
    occurred_end: occurrence.occurredEnd,
    occurred_label: occurrence.occurredLabel,
    item_kind: "entry",
    item_subtype: "entry",
    id: entry.id,
    occurred_start: entry.occurredAt,
    occurred_timezone: entry.occurredTimezone,
    owner_id: context.userId,
    metadata: metadataWithEntryRichText(bodyRich),
    title: entry.title,
  });

  if (error) {
    if (isDeletedForever(error))
      return { message: deletedForeverMessage, status: "rejected" };

    // A lost response may hide an insert that succeeded, so an existing Entry
    // counts as synced whatever the error was, unless it is now in Trash.
    const existing = await existingEntry(entry.id, context);
    if (existing === "trashed")
      return {
        message:
          entry.attachments.length > 0
            ? trashedPhotoMessage
            : trashedEntryMessage,
        status: "rejected",
      };
    if (existing !== "active") {
      const failure = classifySyncFailure({ code: error.code, status });
      // Only a confirmed absence makes a refusal final; an unanswered lookup
      // could hide an Entry an earlier attempt already created.
      return entrySyncFailure(
        existing === null && failure === "rejected" ? "unavailable" : failure,
      );
    }
  }

  revalidatePath("/");
  revalidatePath("/library");

  if (entry.attachments.length === 0) await finishInboxCapture(entry.id);
  return {
    message: "Saved to Library.",
    status: "synced",
  };
}

/** Runs once the capture's originals are registered, never once per photo. */
export async function finishInboxCapture(entryId: string) {
  // Suggestions are this step's only work, so a paused capture ends here.
  if (!AI_CAPABILITIES_AVAILABLE) return;
  const context = await getAuthenticatedContext();
  if (!context) return;
  // Registering photos leaves the Entry at the revision its capture made.
  after(async () => {
    await suggestForEntry(context.client, context.userId, entryId, 1).catch(
      () => undefined,
    );
  });
}

export async function reviewInboxEntry(
  input: InboxReviewInput,
): Promise<ReviewInboxEntryResult> {
  const parsedInput = parseInboxReviewInput(input);

  if (!parsedInput.success) {
    return { message: parsedInput.message, status: "error" };
  }

  const context = await getAuthenticatedContext();

  if (!context) {
    return {
      message: "Your session expired. Sign in again before saving.",
      status: "error",
    };
  }

  const { data, error } = await context.client.rpc("save_entry", {
    p_body_rich: parsedInput.data.bodyRich ?? null,
    p_photo_location: parsedInput.data.photoLocation ?? null,
    p_primary_location: parsedInput.data.location,
    p_body: parsedInput.data.body,
    p_entry_id: parsedInput.data.id,
    p_expected_revision: parsedInput.data.revision,
    p_occurred_start: parsedInput.data.occurredAt,
    p_occurred_end: parsedInput.data.occurredEnd ?? null,
    p_occurred_label: parsedInput.data.occurredLabel ?? null,
    p_date_precision: parsedInput.data.datePrecision ?? "exact",
    p_occurred_timezone: parsedInput.data.occurredTimezone,
    p_tag_names: parsedInput.data.tagNames,
    p_title: parsedInput.data.title,
  });

  if (error?.code === "40001")
    return {
      status: "conflict",
      message:
        "The photo or Location changed. Close this editor, refresh, and confirm the latest version before saving.",
    };

  if (error) {
    return {
      message: "MemoTrail could not save these changes. Try again.",
      status: "error",
    };
  }

  if (
    !Array.isArray(data) ||
    data.length === 0 ||
    typeof data[0]?.revision !== "number"
  ) {
    return {
      message:
        "This Entry changed on another device. Close it, refresh, and edit the latest version.",
      status: "conflict",
    };
  }

  revalidatePath("/");
  revalidatePath("/library");
  revalidatePath("/search");
  return {
    message: "Changes saved.",
    status: "saved",
    revision: data[0].revision,
  };
}

function entrySyncFailure(failure: SyncFailure): SyncInboxEntryResult {
  if (failure === "rejected")
    return { message: rejectedEntryMessage, status: "rejected" };
  // Signing in again fixes every waiting capture, so it still waits in order.
  if (failure === "session")
    return {
      message: "Your session expired. Sign in again to sync this Entry.",
      status: "retry",
    };
  return {
    message: "Saved on this device. MemoTrail will retry when you are online.",
    status: "retry",
  };
}

function photoSyncFailure(
  failure: SyncFailure,
  originalOnDevice = true,
): SyncInboxEntryResult {
  if (failure === "rejected")
    return { message: rejectedPhotoMessage, status: "rejected" };
  if (failure === "session")
    return { message: photoSessionMessage, status: "retry" };
  return {
    message: originalOnDevice
      ? "The photo is saved on this device. MemoTrail will retry attaching it."
      : "MemoTrail will retry attaching this Entry's photos when you are online.",
    status: "retry",
  };
}

/** Where the Entry is, or null when MemoTrail could not answer. */
async function existingEntry(
  entryId: string,
  context: NonNullable<Awaited<ReturnType<typeof getAuthenticatedContext>>>,
): Promise<"active" | "absent" | "trashed" | null> {
  const { data, error } = await context.client
    .from("entries")
    .select("id,deleted_at")
    .eq("id", entryId)
    .eq("owner_id", context.userId)
    .maybeSingle<{ deleted_at: string | null; id: string }>();

  if (error) return null;
  if (data?.id !== entryId) return "absent";
  return data.deleted_at ? "trashed" : "active";
}
