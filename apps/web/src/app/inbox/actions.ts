"use server";

import { revalidatePath } from "next/cache";
import { getAuthenticatedContext } from "@/lib/data/inbox";
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

  const { data, error } = await context.client
    .from("entries")
    .update({
      body: parsedInput.data.body,
      entry_type: parsedInput.data.entryType,
      inbox_status: intent === "done" ? "organized" : "unreviewed",
      occurred_start: parsedInput.data.occurredAt,
      occurred_timezone: parsedInput.data.occurredTimezone,
      title: parsedInput.data.title,
    })
    .eq("id", parsedInput.data.id)
    .eq("owner_id", context.userId)
    .eq("inbox_status", "unreviewed")
    .eq("revision", parsedInput.data.revision)
    .select("id")
    .maybeSingle<{ id: string }>();

  if (error) {
    return {
      message: "MemoTrail could not save these changes. Try again.",
      status: "error",
    };
  }

  if (!data) {
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
