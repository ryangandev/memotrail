"use server";

import { revalidatePath } from "next/cache";
import { writingRevision } from "@/lib/media/writing-revision";
import {
  isFirstTimeUuid,
  parseFirstTimeAttachmentInput,
  type FirstTimeAttachmentInput,
} from "@/lib/data/first-time-input";
import {
  isHomeEntryIdentity,
  parseHomeEntryInput,
  type HomeEntryInput,
} from "@/lib/data/home-record-input";
import {
  parseCaptureExtractionReference,
  type CaptureExtractionReference,
} from "@/lib/data/capture-extraction-input";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import {
  validLocationSelection,
  type ProviderLocation,
} from "@/lib/locations/location";

export type HomeActionResult = {
  entry: { id: string; placeId: string | null; revision: number } | null;
  message: string;
  status: "conflict" | "created" | "error" | "saved" | "trashed";
};

export async function saveHomeEntry(
  input: HomeEntryInput,
  sourceCapture: CaptureExtractionReference | null = null,
  providerLocation: ProviderLocation | null = null,
): Promise<HomeActionResult> {
  const parsed = parseHomeEntryInput(input);

  if (!parsed.success) {
    return result("error", parsed.message);
  }

  const context = await getAuthenticatedContext();

  if (!context) {
    return expiredSession();
  }

  const source = sourceCapture
    ? parseCaptureExtractionReference(sourceCapture)
    : null;
  if (sourceCapture && (!source || parsed.data.id !== null)) {
    return result(
      "error",
      "This Capture handoff is invalid. Return to Inbox and try again.",
    );
  }

  if (providerLocation) {
    if (
      !validLocationSelection(providerLocation) ||
      providerLocation.kind !== "provider" ||
      parsed.data.placeId !== null ||
      parsed.data.placeName !== providerLocation.name ||
      parsed.data.address !== providerLocation.address ||
      parsed.data.city !== providerLocation.city ||
      parsed.data.region !== providerLocation.region ||
      parsed.data.country !== providerLocation.country ||
      parsed.data.latitude !== providerLocation.latitude ||
      parsed.data.longitude !== providerLocation.longitude
    ) {
      return result(
        "error",
        "Choose the address again before saving this Home.",
      );
    }
  }

  const parameters = {
    p_address: parsed.data.address,
    p_body: parsed.data.body,
    p_city: parsed.data.city,
    p_country: parsed.data.country,
    p_date_precision: parsed.data.datePrecision,
    p_latitude: parsed.data.latitude,
    p_longitude: parsed.data.longitude,
    p_move_in_reason: parsed.data.moveInReason,
    p_move_out_reason: parsed.data.moveOutReason,
    p_occurred_end: parsed.data.occurredEnd,
    p_occurred_label: parsed.data.occurredLabel,
    p_occurred_start: parsed.data.occurredStart,
    p_occurred_timezone: parsed.data.occurredTimezone,
    p_place_id: parsed.data.placeId,
    p_place_name: parsed.data.placeName,
    p_place_notes: parsed.data.placeNotes,
    p_region: parsed.data.region,
    p_tag_names: parsed.data.tagNames,
    p_title: parsed.data.title,
  };
  const expectedRevision = source
    ? null
    : await writingRevision(
        context.client,
        parsed.data.id,
        parsed.data.revision,
      );
  const { data, error } = providerLocation
    ? await context.client.rpc("save_home_entry_with_geoapify", {
        p_input: { ...parsed.data, revision: expectedRevision },
        p_source: source,
        p_provider_location: providerLocation,
      })
    : source
      ? await context.client.rpc("extract_capture_to_home", {
          ...parameters,
          p_capture_id: source.id,
          p_capture_revision: source.revision,
        })
      : await context.client.rpc("save_home_entry_with_occurrence", {
          ...parameters,
          p_entry_id: parsed.data.id,
          p_expected_revision: expectedRevision,
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

  const payload = providerLocation ? [data] : data;
  const saved = source ? extractedHome(payload) : savedHome(payload);
  if (!saved) {
    return result(
      "conflict",
      parsed.data.id
        ? "This Home changed on another device. Close it, refresh, and try again."
        : source
          ? "This Capture changed or was already organized. Return to Inbox and refresh."
          : "MemoTrail could not create this Home. Refresh and try again.",
    );
  }

  refreshHomePaths();
  return {
    entry: saved,
    message: parsed.data.id
      ? "Home saved."
      : source
        ? "Home created from Capture."
        : "Home added.",
    status: parsed.data.id ? "saved" : "created",
  };
}

export async function registerHomeAttachment(
  input: FirstTimeAttachmentInput,
): Promise<HomeActionResult> {
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
  if (!isFirstTimeUuid(input.attachmentId)) {
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
    "place_id" in item &&
    "revision" in item &&
    typeof item.entry_id === "string" &&
    (item.place_id === null || typeof item.place_id === "string") &&
    typeof item.revision === "number"
    ? { id: item.entry_id, placeId: item.place_id, revision: item.revision }
    : null;
}

function extractedHome(value: unknown) {
  if (!Array.isArray(value) || value.length === 0) return null;
  const item = value[0];
  return typeof item === "object" &&
    item !== null &&
    "home_entry_id" in item &&
    "home_revision" in item &&
    "place_id" in item &&
    typeof item.home_entry_id === "string" &&
    typeof item.home_revision === "number" &&
    (item.place_id === null || typeof item.place_id === "string")
    ? {
        id: item.home_entry_id,
        placeId: item.place_id,
        revision: item.home_revision,
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
  revalidatePath("/inbox");
  revalidatePath("/library");
  revalidatePath("/search");
  revalidatePath("/timeline");
  revalidatePath("/trash");
}
