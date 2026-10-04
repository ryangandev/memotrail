"use server";

import { revalidatePath } from "next/cache";
import {
  isEntryUuid,
  parseEntryAttachmentInput,
  type EntryAttachmentInput,
} from "@/lib/data/entry-photo-input";
import {
  isHomeEntryIdentity,
  parseHomeEntryInput,
  type HomeEntryInput,
} from "@/lib/data/home-record-input";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import {
  validLocationInput,
  type LocationInput,
} from "@/lib/locations/location";

export type HomeActionResult = {
  /** locationId is the saved primary Location when the save set one. */
  entry: { id: string; revision: number; locationId?: string | null } | null;
  message: string;
  status: "conflict" | "created" | "error" | "saved" | "trashed";
};

/** A Location of undefined leaves the Home's Location unchanged; null removes it. */
export async function saveHomeEntry(
  input: HomeEntryInput,
  location?: LocationInput | null,
): Promise<HomeActionResult> {
  const parsed = parseHomeEntryInput(input);

  if (!parsed.success) {
    return result("error", parsed.message);
  }
  if (location != null && !validLocationInput(location)) {
    return result("error", "Choose the address again before saving this Home.");
  }

  const context = await getAuthenticatedContext();

  if (!context) {
    return expiredSession();
  }

  const { data, error } =
    location !== undefined
      ? await context.client.rpc("save_home_with_location", {
          p_input: parsed.data,
          p_location: location,
        })
      : await context.client.rpc("save_home_entry_with_occurrence", {
          p_body: parsed.data.body,
          p_date_precision: parsed.data.datePrecision,
          p_entry_id: parsed.data.id,
          p_expected_revision: parsed.data.revision,
          p_move_in_reason: parsed.data.moveInReason,
          p_move_out_reason: parsed.data.moveOutReason,
          p_occurred_end: parsed.data.occurredEnd,
          p_occurred_label: parsed.data.occurredLabel,
          p_occurred_start: parsed.data.occurredStart,
          p_occurred_timezone: parsed.data.occurredTimezone,
          p_tag_names: parsed.data.tagNames,
          p_title: parsed.data.title,
        });

  if (error?.code === "40001") {
    return result(
      "conflict",
      "This Home changed on another device. Close it, refresh, and try again.",
    );
  }
  if (error) {
    return result("error", "MemoTrail could not save this Home. Try again.");
  }

  const saved = savedHome(data);
  if (!saved) {
    return result(
      "conflict",
      parsed.data.id
        ? "This Home changed on another device. Close it, refresh, and try again."
        : "MemoTrail could not create this Home. Refresh and try again.",
    );
  }

  refreshHomePaths();
  return {
    entry: saved,
    message: parsed.data.id ? "Home saved." : "Home added.",
    status: parsed.data.id ? "saved" : "created",
  };
}

export async function registerHomeAttachment(
  input: EntryAttachmentInput,
): Promise<HomeActionResult> {
  const parsed = parseEntryAttachmentInput(input);

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

  refreshHomePaths();
  return result("saved", "Photo attached.");
}

export async function trashHomeAttachment(input: {
  attachmentId: string;
}): Promise<HomeActionResult> {
  if (!isEntryUuid(input.attachmentId)) {
    return result(
      "error",
      "This photo reference is invalid. Refresh and try again.",
    );
  }

  const context = await getAuthenticatedContext();
  if (!context) {
    return expiredSession();
  }

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

  refreshHomePaths();
  return result("trashed", "Photo moved to Trash.");
}

export async function trashHomeEntry(input: {
  id: string;
  revision: number;
}): Promise<HomeActionResult> {
  if (!isHomeEntryIdentity(input.id, input.revision)) {
    return result(
      "error",
      "This Home version is invalid. Refresh and try again.",
    );
  }

  const context = await getAuthenticatedContext();
  if (!context) {
    return expiredSession();
  }

  const { data, error } = await context.client.rpc("trash_home_entry", {
    p_entry_id: input.id,
    p_expected_revision: input.revision,
  });

  if (error) {
    return result(
      "error",
      "MemoTrail could not move this Home to Trash. Try again.",
    );
  }

  if (!Array.isArray(data) || data.length === 0) {
    return result(
      "conflict",
      "This Home changed on another device. Close it, refresh, and try again.",
    );
  }

  refreshHomePaths();
  return result("trashed", "Home moved to Trash.");
}

function savedHome(value: unknown) {
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
    ? {
        id: item.entry_id,
        revision: item.revision,
        locationId:
          "location_id" in item && typeof item.location_id === "string"
            ? item.location_id
            : null,
      }
    : null;
}

function result(
  status: HomeActionResult["status"],
  message: string,
): HomeActionResult {
  return { entry: null, message, status };
}

function expiredSession(): HomeActionResult {
  return result(
    "error",
    "Your session expired. Sign in again before continuing.",
  );
}

function refreshHomePaths() {
  revalidatePath("/");
  revalidatePath("/homes");
  revalidatePath("/library");
  revalidatePath("/search");
  revalidatePath("/timeline");
  revalidatePath("/trash");
}
