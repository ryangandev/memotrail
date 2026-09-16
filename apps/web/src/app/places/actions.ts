"use server";

import { revalidatePath } from "next/cache";
import {
  isPlaceIdentity,
  parsePlaceRecordInput,
  type PlaceRecordInput,
} from "@/lib/data/place-record-input";
import { getAuthenticatedContext } from "@/lib/data/inbox";

export type PlaceActionResult = {
  message: string;
  place: { id: string; revision: number } | null;
  status: "conflict" | "created" | "error" | "saved" | "trashed";
};

export async function savePlace(
  input: PlaceRecordInput,
): Promise<PlaceActionResult> {
  const parsed = parsePlaceRecordInput(input);
  if (!parsed.success) return result("error", parsed.message);

  const context = await getAuthenticatedContext();
  if (!context) return expiredSession();

  const { data, error } = await context.client.rpc("save_place", {
    p_address: parsed.data.address,
    p_city: parsed.data.city,
    p_country: parsed.data.country,
    p_expected_revision: parsed.data.revision,
    p_latitude: parsed.data.latitude,
    p_longitude: parsed.data.longitude,
    p_name: parsed.data.name,
    p_notes: parsed.data.notes,
    p_place_id: parsed.data.id,
    p_region: parsed.data.region,
    p_related_entry_ids: parsed.data.relatedEntryIds,
  });
  if (error) {
    return result("error", "MemoTrail could not save this Place. Try again.");
  }

  const saved = savedPlace(data);
  if (!saved) {
    return result(
      "conflict",
      parsed.data.id
        ? "This Place changed on another device. Close it, refresh, and try again."
        : "MemoTrail could not create this Place. Refresh and try again.",
    );
  }

  refreshPlacePaths();
  return {
    message: parsed.data.id ? "Place saved." : "Place added.",
    place: saved,
    status: parsed.data.id ? "saved" : "created",
  };
}

export async function trashPlace(input: {
  id: string;
  revision: number;
}): Promise<PlaceActionResult> {
  if (!isPlaceIdentity(input.id, input.revision)) {
    return result(
      "error",
      "This Place version is invalid. Refresh and try again.",
    );
  }

  const context = await getAuthenticatedContext();
  if (!context) return expiredSession();

  const { data, error } = await context.client.rpc("trash_place", {
    p_expected_revision: input.revision,
    p_place_id: input.id,
  });
  if (error) {
    return result(
      "error",
      "MemoTrail could not move this Place to Trash. Try again.",
    );
  }
  if (!Array.isArray(data) || data.length === 0) {
    return result(
      "conflict",
      "This Place changed or is still linked to an Item. Refresh and unlink it before trying again.",
    );
  }

  refreshPlacePaths();
  return result("trashed", "Place moved to Trash.");
}

function savedPlace(value: unknown) {
  if (!Array.isArray(value) || value.length === 0) return null;
  const item = value[0];
  return typeof item === "object" &&
    item !== null &&
    "place_id" in item &&
    "revision" in item &&
    typeof item.place_id === "string" &&
    typeof item.revision === "number"
    ? { id: item.place_id, revision: item.revision }
    : null;
}

function result(
  status: PlaceActionResult["status"],
  message: string,
): PlaceActionResult {
  return { message, place: null, status };
}

function expiredSession(): PlaceActionResult {
  return result(
    "error",
    "Your session expired. Sign in again before continuing.",
  );
}

function refreshPlacePaths() {
  for (const path of [
    "/",
    "/homes",
    "/library",
    "/places",
    "/search",
    "/trash",
  ]) {
    revalidatePath(path);
  }
}
