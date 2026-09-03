"use server";

import { revalidatePath } from "next/cache";
import {
  isFirstTimeUuid,
  parseFirstTimeAttachmentInput,
  type FirstTimeAttachmentInput,
} from "@/lib/data/first-time-input";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import {
  isVehicleEntryIdentity,
  parseVehicleEntryInput,
  type VehicleEntryInput,
} from "@/lib/data/vehicle-record-input";

export type VehicleActionResult = {
  entry: { id: string; revision: number } | null;
  message: string;
  status: "conflict" | "created" | "error" | "saved" | "trashed";
};

export async function saveVehicleEntry(
  input: VehicleEntryInput,
): Promise<VehicleActionResult> {
  const parsed = parseVehicleEntryInput(input);
  if (!parsed.success) return result("error", parsed.message);

  const context = await getAuthenticatedContext();
  if (!context) return expiredSession();

  const { data, error } = await context.client.rpc("save_vehicle_entry", {
    p_body: parsed.data.body,
    p_collection_names: parsed.data.collectionNames,
    p_color: parsed.data.color,
    p_date_precision: parsed.data.datePrecision,
    p_entry_id: parsed.data.id,
    p_expected_revision: parsed.data.revision,
    p_make: parsed.data.make,
    p_model: parsed.data.model,
    p_model_year: parsed.data.modelYear,
    p_occurred_end: parsed.data.occurredEnd,
    p_occurred_label: parsed.data.occurredLabel,
    p_occurred_start: parsed.data.occurredStart,
    p_occurred_timezone: parsed.data.occurredTimezone,
    p_tag_names: parsed.data.tagNames,
    p_title: parsed.data.title,
  });

  if (error) {
    return result("error", "MemoTrail could not save this Vehicle. Try again.");
  }

  const saved = savedVehicle(data);
  if (!saved) {
    return result(
      "conflict",
      parsed.data.id
        ? "This Vehicle changed on another device. Close it, refresh, and try again."
        : "MemoTrail could not create this Vehicle. Refresh and try again.",
    );
  }

  refreshVehiclePaths();
  return {
    entry: saved,
    message: parsed.data.id ? "Vehicle saved." : "Vehicle added.",
    status: parsed.data.id ? "saved" : "created",
  };
}

export async function registerVehicleAttachment(
  input: FirstTimeAttachmentInput,
): Promise<VehicleActionResult> {
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

  refreshVehiclePaths();
  return result("saved", "Photo attached.");
}

export async function trashVehicleAttachment(input: {
  attachmentId: string;
}): Promise<VehicleActionResult> {
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

  refreshVehiclePaths();
  return result("trashed", "Photo moved to Trash.");
}

export async function trashVehicleEntry(input: {
  id: string;
  revision: number;
}): Promise<VehicleActionResult> {
  if (!isVehicleEntryIdentity(input.id, input.revision)) {
    return result(
      "error",
      "This Vehicle version is invalid. Refresh and try again.",
    );
  }

  const context = await getAuthenticatedContext();
  if (!context) return expiredSession();

  const { data, error } = await context.client.rpc("trash_vehicle_entry", {
    p_entry_id: input.id,
    p_expected_revision: input.revision,
  });
  if (error) {
    return result(
      "error",
      "MemoTrail could not move this Vehicle to Trash. Try again.",
    );
  }
  if (!Array.isArray(data) || data.length === 0) {
    return result(
      "conflict",
      "This Vehicle changed on another device. Close it, refresh, and try again.",
    );
  }

  refreshVehiclePaths();
  return result("trashed", "Vehicle moved to Trash.");
}

function savedVehicle(value: unknown) {
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

function result(
  status: VehicleActionResult["status"],
  message: string,
): VehicleActionResult {
  return { entry: null, message, status };
}

function expiredSession(): VehicleActionResult {
  return result(
    "error",
    "Your session expired. Sign in again before continuing.",
  );
}

function refreshVehiclePaths() {
  revalidatePath("/");
  revalidatePath("/collections");
  revalidatePath("/library");
  revalidatePath("/search");
  revalidatePath("/timeline");
  revalidatePath("/trash");
  revalidatePath("/vehicles");
}
