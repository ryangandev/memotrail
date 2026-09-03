import {
  firstTimePhotoLimit,
  firstTimePhotoSizeLimit,
  inferFirstTimeImageMimeType,
  type FirstTimeImageMimeType,
} from "./first-time-input";

export const inboxPhotoLimit = firstTimePhotoLimit;
export const inboxPhotoSizeLimit = firstTimePhotoSizeLimit;

export type InboxPhotoDraft = {
  file: File;
  id: string;
  mimeType: FirstTimeImageMimeType;
};

export type QueuedInboxAttachment = {
  id: string;
  lastModified: number;
  mimeType: FirstTimeImageMimeType;
  name: string;
  size: number;
};

export type InboxPhotoSelection = {
  accepted: InboxPhotoDraft[];
  message: string | null;
};

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function validateInboxPhotoFiles(
  files: File[],
  currentCount: number,
): InboxPhotoSelection {
  const availableCount = Math.max(0, inboxPhotoLimit - currentCount);
  const accepted: InboxPhotoDraft[] = [];
  let message: string | null = null;

  for (const file of files.slice(0, availableCount)) {
    const mimeType = inferFirstTimeImageMimeType(file.name, file.type);

    if (!mimeType) {
      message ??= "Use JPEG, PNG, WebP, HEIC, or HEIF photos.";
      continue;
    }

    if (file.size < 1 || file.size > inboxPhotoSizeLimit) {
      message ??= "Each photo must be no larger than 50 MB.";
      continue;
    }

    if (file.name.length > 255) {
      message ??= "Photo filenames can be up to 255 characters.";
      continue;
    }

    accepted.push({ file, id: crypto.randomUUID(), mimeType });
  }

  if (files.length > availableCount) {
    message ??= `Keep up to ${inboxPhotoLimit} photos with one Entry.`;
  }

  return { accepted, message };
}

export function queuedInboxAttachment(
  draft: InboxPhotoDraft,
): QueuedInboxAttachment {
  return {
    id: draft.id,
    lastModified: draft.file.lastModified,
    mimeType: draft.mimeType,
    name: draft.file.name,
    size: draft.file.size,
  };
}

export function isQueuedInboxAttachment(
  value: unknown,
): value is QueuedInboxAttachment {
  if (typeof value !== "object" || value === null) {
    return false;
  }

  const photo = value as Partial<QueuedInboxAttachment>;

  return (
    typeof photo.id === "string" &&
    uuidPattern.test(photo.id) &&
    typeof photo.name === "string" &&
    photo.name.length <= 255 &&
    typeof photo.mimeType === "string" &&
    inferFirstTimeImageMimeType(photo.name, photo.mimeType) ===
      photo.mimeType &&
    typeof photo.size === "number" &&
    Number.isSafeInteger(photo.size) &&
    photo.size >= 1 &&
    photo.size <= inboxPhotoSizeLimit &&
    typeof photo.lastModified === "number" &&
    Number.isSafeInteger(photo.lastModified) &&
    photo.lastModified >= 0
  );
}
