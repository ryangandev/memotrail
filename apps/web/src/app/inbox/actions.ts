"use server";

import { revalidatePath } from "next/cache";
import { after } from "next/server";
import { suggestForEntry } from "@/lib/ai/suggestions-server";
import { writingRevision } from "@/lib/media/writing-revision";
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

export type SyncInboxEntryResult = {
  message: string;
  status: "retry" | "synced";
};

export type ReviewInboxEntryResult =
  | { message: string; status: "conflict" | "error" }
  | { message: string; status: "done" | "saved"; revision: number };

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
  bodyRichJson: string | null = null,
): Promise<SyncInboxEntryResult> {
  if (!isQueuedInboxEntry(input)) {
    return {
      message: "This queued Entry is invalid and needs your attention.",
      status: "retry",
    };
  }

  const bodyRich = parseEntryRichTextJson(bodyRichJson, input.body);
  const entry: QueuedInboxEntry = { ...input, bodyRich };

  if (bodyRichJson !== null && bodyRich === null) {
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

  const occurrence = queuedOccurrence(entry);
  const { error } = await context.client.from("entries").insert({
    body: entry.body,
    client_id: `web:${entry.id}`,
    date_precision: occurrence.datePrecision,
    occurred_end: occurrence.occurredEnd,
    occurred_label: occurrence.occurredLabel,
    entry_type: "standard",
    id: entry.id,
    inbox_status: "unreviewed",
    occurred_start: entry.occurredAt,
    occurred_timezone: entry.occurredTimezone,
    owner_id: context.userId,
    metadata: metadataWithEntryRichText(bodyRich),
    title: entry.title,
  });

  if (error && !(await entryAlreadyExists(entry.id, context))) {
    return {
      message:
        "Saved on this device. MemoTrail will retry when you are online.",
      status: "retry",
    };
  }

  revalidatePath("/");

  if (entry.attachments.length === 0) await finishInboxCapture(entry.id);
  return {
    message: "Saved to Inbox.",
    status: "synced",
  };
}

/** Runs once the capture's originals are registered, never once per photo. */
export async function finishInboxCapture(entryId: string) {
  const context = await getAuthenticatedContext();
  if (!context) return;
  const revision = await writingRevision(context.client, entryId, 1);
  after(async () => {
    await suggestForEntry(
      context.client,
      context.userId,
      entryId,
      revision ?? 1,
    ).catch(() => undefined);
  });
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

  const { data, error } = await context.client.rpc(
    "review_entry_with_photo_place_rich",
    {
      p_body_rich: parsedInput.data.bodyRich ?? null,
      p_photo_place: parsedInput.data.photoPlace ?? null,
      p_body: parsedInput.data.body,
      p_collection_names: parsedInput.data.collectionNames,
      p_entry_id: parsedInput.data.id,
      p_entry_type: parsedInput.data.entryType,
      p_expected_revision: parsedInput.data.revision,
      p_mark_done: intent === "done",
      p_occurred_start: parsedInput.data.occurredAt,
      p_occurred_end: parsedInput.data.occurredEnd ?? null,
      p_occurred_label: parsedInput.data.occurredLabel ?? null,
      p_date_precision: parsedInput.data.datePrecision ?? "exact",
      p_occurred_timezone: parsedInput.data.occurredTimezone,
      p_tag_names: parsedInput.data.tagNames,
      p_title: parsedInput.data.title,
    },
  );

  if (error?.code === "40001")
    return {
      status: "conflict",
      message:
        "The photo or Place changed. Close this review, refresh, and confirm the latest version before saving.",
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
        "This Entry changed on another device. Close it, refresh, and review the latest version.",
      status: "conflict",
    };
  }

  revalidatePath("/");

  revalidatePath("/inbox");
  revalidatePath("/places");
  revalidatePath("/search");
  return intent === "done"
    ? {
        message: "Entry organized.",
        status: "done",
        revision: data[0].revision,
      }
    : {
        message: "Changes saved.",
        status: "saved",
        revision: data[0].revision,
      };
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
