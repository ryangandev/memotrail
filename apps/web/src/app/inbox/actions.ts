"use server";

import { revalidatePath } from "next/cache";
import {
  parseInboxEntryInput,
  type InboxEntryInputResult,
} from "@/lib/data/inbox-input";
import { getAuthenticatedContext } from "@/lib/data/inbox";

export type CaptureEntryState = {
  message: string;
  submissionId: string | null;
  type: "idle" | "error" | "success";
};

export async function createInboxEntry(
  _previousState: CaptureEntryState,
  formData: FormData,
): Promise<CaptureEntryState> {
  const input = parseInboxEntryInput(formData);

  if (!input.success) {
    return errorState(input);
  }

  const context = await getAuthenticatedContext();

  if (!context) {
    return {
      message: "Your session expired. Sign in again before saving.",
      submissionId: crypto.randomUUID(),
      type: "error",
    };
  }

  const now = new Date().toISOString();
  const { error } = await context.client.from("entries").insert({
    body: input.data.body,
    date_precision: "exact",
    entry_type: "standard",
    inbox_status: "unreviewed",
    occurred_start: now,
    occurred_timezone: "UTC",
    owner_id: context.userId,
    title: input.data.title,
  });

  if (error) {
    return {
      message: "MemoTrail could not save this Entry. Your text is still here.",
      submissionId: crypto.randomUUID(),
      type: "error",
    };
  }

  revalidatePath("/");

  return {
    message: "Saved to Inbox.",
    submissionId: crypto.randomUUID(),
    type: "success",
  };
}

function errorState(input: Extract<InboxEntryInputResult, { success: false }>) {
  return {
    message: input.message,
    submissionId: crypto.randomUUID(),
    type: "error" as const,
  };
}
