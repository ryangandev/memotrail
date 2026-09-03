"use server";

import { revalidatePath } from "next/cache";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import {
  parseFirstTimeAttachmentInput,
  type FirstTimeAttachmentInput,
} from "@/lib/data/first-time-input";
import {
  isQueuedInboxEntry,
  type QueuedInboxEntry,
} from "@/lib/data/inbox-queue";
import {
  parseInboxReviewInput,
  type InboxReviewInput,
} from "@/lib/data/inbox-review";

export type SyncInboxEntryResult = {
  message: string;
  status: "retry" | "synced";
};

export type ReviewInboxEntryResult = {
  message: string;
  status: "conflict" | "done" | "error" | "saved";
};

export async function registerEntryAttachment(
  input: FirstTimeAttachmentInput,
): Promise<SyncInboxEntryResult> {
  const parsed = parseFirstTimeAttachmentInput(input);

  if (!parsed.success) {
    return { message: parsed.message, status: "retry" };
  }

  const context = await getAuthenticatedContext();

  if (!context) {
    return {
      message: "Your session expired before the photo could be attached.",
      status: "retry",
    };
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
    return {
      message:
        "The photo is saved on this device. MemoTrail will retry attaching it.",
      status: "retry",
    };
  }

  revalidatePath("/");
  revalidatePath("/inbox");
  revalidatePath("/search");

  return { message: "Photo attached.", status: "synced" };
}

export async function syncInboxEntry(
  input: QueuedInboxEntry,
): Promise<SyncInboxEntryResult> {
  if (!isQueuedInboxEntry(input)) {
    return {
      message: "This queued Entry is invalid and needs your attention.",
      status: "retry",
    };
  }

  const context = await getAuthenticatedContext();

  if (!context) {
    return {
      message: "Your session expired. Sign in again to sync this Entry.",
      status: "retry",
    };
  }

  const { error } = await context.client.from("entries").insert({
    body: input.body,
    client_id: `web:${input.id}`,
    date_precision: "exact",
    entry_type: "standard",
    id: input.id,
    inbox_status: "unreviewed",
    occurred_start: input.occurredAt,
    occurred_timezone: input.occurredTimezone,
    owner_id: context.userId,
    title: input.title,
  });

  if (error && !(await entryAlreadyExists(input.id, context))) {
    return {
      message:
        "Saved on this device. MemoTrail will retry when you are online.",
      status: "retry",
    };
  }

  revalidatePath("/");

  return {
    message: "Saved to Inbox.",
    status: "synced",
  };
}

export async function reviewInboxEntry(
  input: InboxReviewInput,
  intent: "done" | "save",
): Promise<ReviewInboxEntryResult> {
  const parsedInput = parseInboxReviewInput(input);

  if (!parsedInput.success || (intent !== "save" && intent !== "done")) {
    return {
      message: parsedInput.success
        ? "Choose a valid review action."
        : parsedInput.message,
      status: "error",
    };
  }

  const context = await getAuthenticatedContext();

  if (!context) {
    return {
      message: "Your session expired. Sign in again before saving.",
      status: "error",
    };
  }

  const { data, error } = await context.client.rpc("review_entry", {
    p_body: parsedInput.data.body,
    p_collection_names: parsedInput.data.collectionNames,
    p_entry_id: parsedInput.data.id,
    p_entry_type: parsedInput.data.entryType,
    p_expected_revision: parsedInput.data.revision,
    p_mark_done: intent === "done",
    p_occurred_start: parsedInput.data.occurredAt,
    p_occurred_timezone: parsedInput.data.occurredTimezone,
    p_tag_names: parsedInput.data.tagNames,
    p_title: parsedInput.data.title,
  });

  if (error) {
    return {
      message: "MemoTrail could not save these changes. Try again.",
      status: "error",
    };
  }

  if (!Array.isArray(data) || data.length === 0) {
    return {
      message:
        "This Entry changed on another device. Close it, refresh, and review the latest version.",
      status: "conflict",
    };
  }

  revalidatePath("/");

  return intent === "done"
    ? { message: "Entry organized.", status: "done" }
    : { message: "Changes saved.", status: "saved" };
}

async function entryAlreadyExists(
  entryId: string,
  context: NonNullable<Awaited<ReturnType<typeof getAuthenticatedContext>>>,
) {
  const { data, error } = await context.client
    .from("entries")
    .select("id")
    .eq("id", entryId)
    .eq("owner_id", context.userId)
    .maybeSingle<{ id: string }>();

  return !error && data?.id === entryId;
}
