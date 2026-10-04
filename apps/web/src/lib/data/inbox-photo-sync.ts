import { countLabel } from "@/lib/count-label";
import type { PhotoUploadProgress } from "@/lib/media/upload";
import {
  offlinePhotoSyncMessage,
  photoSessionMessage,
  rejectedPhotoMessage,
  tooLargePhotoMessage,
  unsupportedPhotoMessage,
} from "./capture-sync-messages";
import {
  createFirstTimeObjectPath,
  type FirstTimeAttachmentInput,
} from "./first-time-input";
import type { InboxPhotoDraft } from "./inbox-photo";
import type { QueuedInboxEntry } from "./inbox-queue";
import type { InboxSyncResult } from "./inbox-sync";
import {
  classifyUploadFailure,
  type StorageFailure,
  type UploadFailure,
} from "./sync-failure";

/** The browser and server side of attaching one capture's photos. */
export type CapturePhotoOperations = {
  /** The photos this device still keeps for pending captures. */
  loadPhotos: () => Promise<InboxPhotoDraft[]>;
  /** Uploads an original without overwriting one that is already stored. */
  upload: (
    objectPath: string,
    photo: InboxPhotoDraft,
  ) => Promise<{ error: StorageFailure | null }>;
  register: (
    input: FirstTimeAttachmentInput,
    options: { originalOnDevice: boolean },
  ) => Promise<InboxSyncResult>;
  /** Deletes this device's copy of a photo that reached MemoTrail. */
  removePhoto: (attachmentId: string) => Promise<void>;
  /**
   * Deletes a stored original that MemoTrail refused to register. Storage
   * keeps a registered original, so this only clears an unused upload.
   */
  removeUpload: (objectPath: string) => Promise<void>;
  /**
   * Why the person cannot upload as themselves now, or null while they are
   * still signed in as this owner.
   */
  sessionFailure: () => Promise<"session" | "unavailable" | null>;
};

/**
 * Uploads and registers a capture's photos in order once its Entry exists,
 * removing each local copy after MemoTrail confirms it. Stops at the first
 * photo that must wait or that MemoTrail refuses.
 */
export async function synchronizeCapturePhotos(
  ownerId: string,
  entry: QueuedInboxEntry,
  operations: CapturePhotoOperations,
  onProgress?: (progress: PhotoUploadProgress) => void,
): Promise<InboxSyncResult> {
  const storedPhotos = await operations.loadPhotos();
  const photosById = new Map(storedPhotos.map((photo) => [photo.id, photo]));

  let completed = 0;
  onProgress?.({ completed, total: entry.attachments.length });
  for (const attachment of entry.attachments) {
    const photo = photosById.get(attachment.id);
    const objectPath = createFirstTimeObjectPath(
      ownerId,
      entry.id,
      attachment.id,
      attachment.mimeType,
    );

    if (!objectPath) {
      return {
        message:
          "This Entry is in your Inbox, but one of its photos is invalid on this device, so they will not sync. Discard to remove them from this device.",
        status: "rejected",
      };
    }

    const attachmentInput: FirstTimeAttachmentInput = {
      attachmentId: attachment.id,
      byteSize: attachment.size,
      entryId: entry.id,
      mimeType: attachment.mimeType,
      objectPath,
      originalFilename: attachment.name || null,
      pixelHeight: null,
      pixelWidth: null,
    };

    if (!photo) {
      // An earlier attempt may have stored and registered it before this
      // device removed its copy; otherwise it can never reach MemoTrail.
      const registered = await operations.register(attachmentInput, {
        originalOnDevice: false,
      });
      if (registered.status !== "synced")
        return refusedRegistration(registered, objectPath, operations);
      completed += 1;
      onProgress?.({ completed, total: entry.attachments.length });
      continue;
    }

    if (
      photo.file.name !== attachment.name ||
      photo.file.size !== attachment.size ||
      photo.file.lastModified !== attachment.lastModified ||
      photo.mimeType !== attachment.mimeType
    ) {
      return {
        message:
          "This Entry is in your Inbox, but one of its photos changed on this device, so they will not sync. Discard to remove them from this device.",
        status: "rejected",
      };
    }

    const { error } = await operations.upload(objectPath, photo);
    if (error) {
      let failure = classifyUploadFailure(error);
      if (failure === "denied")
        failure = (await operations.sessionFailure()) ?? "rejected";
      // A stored original continues to registration, which verifies it.
      if (failure !== "exists") return uploadFailureResult(failure);
    }

    const registered = await operations.register(attachmentInput, {
      originalOnDevice: true,
    });

    if (registered.status !== "synced") {
      return refusedRegistration(registered, objectPath, operations);
    }

    try {
      await operations.removePhoto(attachment.id);
    } catch {
      return {
        message:
          "This photo reached MemoTrail, but its local pending copy could not be cleared. Retry to finish.",
        status: "retry",
      };
    }
    completed += 1;
    onProgress?.({ completed, total: entry.attachments.length });
  }

  return {
    message: `Saved to Inbox with ${countLabel(entry.attachments.length, "photo")}.`,
    status: "synced",
  };
}

/**
 * Passes on a registration that did not succeed. A refused one never uses
 * its upload, such as when the Entry went to Trash or was deleted forever
 * while the photo was on its way, so the stored original is cleared too.
 */
async function refusedRegistration(
  result: InboxSyncResult,
  objectPath: string,
  operations: CapturePhotoOperations,
): Promise<InboxSyncResult> {
  if (result.status === "rejected")
    // The refusal stands either way; a failed removal only leaves the file.
    await operations.removeUpload(objectPath).catch(() => undefined);
  return result;
}

function uploadFailureResult(
  failure: Exclude<UploadFailure, "denied" | "exists">,
): InboxSyncResult {
  switch (failure) {
    case "too_large":
      return { message: tooLargePhotoMessage, status: "rejected" };
    case "unsupported_type":
      return { message: unsupportedPhotoMessage, status: "rejected" };
    case "rejected":
      return { message: rejectedPhotoMessage, status: "rejected" };
    case "session":
      // Signing in again fixes every waiting photo, so it still waits in order.
      return { message: photoSessionMessage, status: "retry" };
    case "unavailable":
      return { message: offlinePhotoSyncMessage, status: "retry" };
  }
}
