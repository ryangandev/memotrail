import type { SupabaseClient } from "@supabase/supabase-js";
import { importLimits } from "./limits";
import {
  ImportItemError,
  ImportLeaseLost,
  ImportQuotaError,
  type ClaimedItem,
  type ImportGateway,
  type PhotoReader,
} from "./run";
import type { ImportPayload } from "./scan";
import type { ImportItemMedia, ImportPhotoState } from "./types";
import type { ZipArchive } from "./zip";

type DatabaseError = { code?: string; message?: string; status?: number } | null;

function failure(error: DatabaseError): Error {
  const message = error?.message ?? "";
  if (message.includes("import_lease_lost") || message.includes("import_job_not_running"))
    return new ImportLeaseLost();
  return new Error(message || "The import could not reach the database.");
}

/** The import functions over a signed-in Supabase client. */
export function supabaseGateway(
  client: SupabaseClient,
  jobId: string,
): ImportGateway {
  return {
    async acquireLease() {
      const { data, error } = await client.rpc("acquire_import_lease", {
        p_job_id: jobId,
        p_lease_seconds: importLimits.runLeaseSeconds,
      });
      if (error) throw failure(error);
      return typeof data === "string" ? data : null;
    },

    async releaseLease(token) {
      await client.rpc("release_import_lease", {
        p_job_id: jobId,
        p_lease_token: token,
      });
    },

    async claim(token, limit) {
      const { data, error } = await client.rpc("claim_import_items", {
        p_job_id: jobId,
        p_lease_seconds: importLimits.runLeaseSeconds,
        p_lease_token: token,
        p_limit: limit,
      });
      if (error) throw failure(error);
      return ((data ?? []) as Record<string, unknown>[]).map(
        (row): ClaimedItem => ({
          contentHash: (row.item_content_hash as string | null) ?? null,
          entryId: (row.item_entry_id as string | null) ?? null,
          itemId: row.item_id as string,
          media: (row.media as ImportItemMedia | null) ?? null,
          payload: (row.payload as ImportPayload | null) ?? null,
          sourceKey: row.source_key as string,
          status: row.item_status as "pending" | "photos_pending",
        }),
      );
    },

    async importEntry(args) {
      const { data, error } = await client.rpc("import_entry", {
        p_body: args.body,
        p_body_rich: args.bodyRich,
        p_content_hash: args.contentHash,
        p_date_precision: args.datePrecision,
        p_entry_id: args.entryId,
        p_item_id: args.itemId,
        p_job_id: jobId,
        p_occurred_end: args.occurredEnd,
        p_occurred_label: args.occurredLabel,
        p_occurred_start: args.occurredStart,
        p_occurred_timezone: args.occurredTimezone,
        p_primary_location: args.primaryLocation,
        p_source_created_at: args.sourceCreatedAt,
        p_source_modified_at: args.sourceModifiedAt,
        p_tag_names: args.tagNames,
        p_title: args.title,
      });
      if (error) {
        const message = error.message ?? "";
        if (message.includes("import_job_not_running")) throw new ImportLeaseLost();
        // The database refused this Entry's content. That is final for this item.
        if (error.code === "22023" || message.includes("entry_content_too_long"))
          throw new ImportItemError(
            /^[a-z][a-z0-9_]{0,63}$/.test(message) ? message : "invalid_entry",
          );
        throw failure(error);
      }
      const row = (Array.isArray(data) ? data[0] : data) as
        | { saved_entry_id: string | null; outcome: string }
        | undefined;
      if (!row) throw new ImportItemError("entry_unavailable", true);
      return {
        entryId: row.saved_entry_id,
        outcome: row.outcome as "created",
      };
    },

    async finishItem(itemId, status, reason, retryable, media) {
      const { error } = await client.rpc("finish_import_item", {
        p_item_id: itemId,
        p_media: media,
        p_reason: reason,
        p_retryable: retryable,
        p_status: status,
      });
      if (error) throw failure(error);
    },

    async finishJob() {
      const { data, error } = await client.rpc("finish_import_job", {
        p_job_id: jobId,
      });
      if (error) throw failure(error);
      return typeof data === "string" ? data : "running";
    },

    async pauseForQuota() {
      await client.rpc("update_import_job", {
        p_from: ["running"],
        p_job_id: jobId,
        p_patch: { error_code: "storage_full" },
        p_status: "paused_quota",
      });
    },

    async uploadOriginal(path, bytes, mimeType) {
      const result = await client.storage.from("entry-media").upload(path, bytes, {
        cacheControl: "3600",
        contentType: mimeType,
        upsert: false,
      });
      if (!result.error) return;
      const status = Number((result.error as { statusCode?: string }).statusCode);
      const message = result.error.message ?? "";
      // An interrupted upload may already be there. Registration checks the object.
      if (status === 409 || /already exists|duplicate/i.test(message)) return;
      if (status === 507 || /quota|insufficient storage|storage limit/i.test(message))
        throw new ImportQuotaError(message);
      throw new Error(message);
    },

    async registerPhoto(input) {
      const { error } = await client.rpc("register_entry_attachment", {
        p_attachment_id: input.attachmentId,
        p_byte_size: input.byteSize,
        p_entry_id: input.entryId,
        p_mime_type: input.mimeType,
        p_object_path: input.objectPath,
        p_original_filename: input.originalFilename,
        p_pixel_height: null,
        p_pixel_width: null,
      });
      if (!error) return;
      const message = error.message ?? "";
      if (message.includes("entry_in_trash"))
        throw new ImportItemError("entry_in_trash");
      if (message.includes("entry_deleted_forever"))
        throw new ImportItemError("entry_deleted_forever");
      if (message.includes("attachment_conflict"))
        throw new ImportItemError("photo_conflict", true);
      throw new Error(message);
    },
  };
}

/** Reads a job's photos out of its archive. */
export function archivePhotoReader(archive: ZipArchive, maxBytes: number): PhotoReader {
  return {
    async read(photo: ImportPhotoState) {
      const member = archive.find(photo.zipPath, photo.container);
      if (!member) throw new Error("missing");
      return archive.readBuffer(member, maxBytes);
    },
  };
}
