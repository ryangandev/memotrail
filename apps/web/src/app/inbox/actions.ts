"use server";

import { revalidatePath } from "next/cache";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import {
  isQueuedInboxEntry,
  type QueuedInboxEntry,
} from "@/lib/data/inbox-queue";

export type SyncInboxEntryResult = {
  message: string;
  status: "retry" | "synced";
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
