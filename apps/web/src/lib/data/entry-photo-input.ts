// Photo uploads shared by every Entry with photos: Entries, Homes, Vehicles, and Goals.
export const entryPhotoLimit = 12;
export const entryPhotoSizeLimit = 50 * 1024 * 1024;

export const entryImageMimeTypes = [
  "image/jpeg",
  "image/png",
  "image/webp",
  "image/heic",
  "image/heif",
] as const;

export type EntryImageMimeType = (typeof entryImageMimeTypes)[number];

export type EntryAttachmentInput = {
  attachmentId: string;
  byteSize: number;
  entryId: string;
  mimeType: EntryImageMimeType;
  objectPath: string;
  originalFilename: string | null;
  pixelHeight: number | null;
  pixelWidth: number | null;
};

type Parsed<T> =
  { data: T; success: true } | { message: string; success: false };

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const mimeTypeExtensions: Record<EntryImageMimeType, string> = {
  "image/heic": "heic",
  "image/heif": "heif",
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
};

export function parseEntryAttachmentInput(
  input: unknown,
): Parsed<EntryAttachmentInput> {
  if (!isRecord(input)) {
    return invalid("This photo is invalid. Select it again.");
  }

  const mimeType = normalizeEntryImageMimeType(input.mimeType);
  const originalFilename =
    typeof input.originalFilename === "string"
      ? input.originalFilename.trim() || null
      : null;

  if (
    typeof input.attachmentId !== "string" ||
    !uuidPattern.test(input.attachmentId) ||
    typeof input.entryId !== "string" ||
    !uuidPattern.test(input.entryId) ||
    typeof input.objectPath !== "string" ||
    !input.objectPath.trim()
  ) {
    return invalid("This photo reference is invalid. Select it again.");
  }

  if (!mimeType) {
    return invalid("Use a JPEG, PNG, WebP, HEIC, or HEIF image.");
  }

  if (
    typeof input.byteSize !== "number" ||
    !Number.isSafeInteger(input.byteSize) ||
    input.byteSize < 1 ||
    input.byteSize > entryPhotoSizeLimit
  ) {
    return invalid("Each photo must be no larger than 50 MB.");
  }

  if (originalFilename && originalFilename.length > 255) {
    return invalid("Photo filenames can be up to 255 characters.");
  }

  const pixelWidth = optionalPositiveInteger(input.pixelWidth);
  const pixelHeight = optionalPositiveInteger(input.pixelHeight);

  if (pixelWidth === undefined || pixelHeight === undefined) {
    return invalid("This photo has invalid dimensions.");
  }

  return {
    data: {
      attachmentId: input.attachmentId,
      byteSize: input.byteSize,
      entryId: input.entryId,
      mimeType,
      objectPath: input.objectPath.trim(),
      originalFilename,
      pixelHeight,
      pixelWidth,
    },
    success: true,
  };
}

export function createEntryObjectPath(
  ownerId: string,
  entryId: string,
  attachmentId: string,
  mimeType: string,
) {
  const normalizedMimeType = normalizeEntryImageMimeType(mimeType);

  if (
    !uuidPattern.test(ownerId) ||
    !uuidPattern.test(entryId) ||
    !uuidPattern.test(attachmentId) ||
    !normalizedMimeType
  ) {
    return null;
  }

  return `${ownerId}/${entryId}/${attachmentId}.${mimeTypeExtensions[normalizedMimeType]}`;
}

export function normalizeEntryImageMimeType(value: unknown) {
  if (typeof value !== "string") {
    return null;
  }

  const normalized = value.trim().toLocaleLowerCase();
  return entryImageMimeTypes.includes(normalized as EntryImageMimeType)
    ? (normalized as EntryImageMimeType)
    : null;
}

export function inferEntryImageMimeType(name: string, declaredType: string) {
  const declared = normalizeEntryImageMimeType(declaredType);

  if (declared) {
    return declared;
  }

  const extension = name.trim().toLocaleLowerCase().split(".").pop();
  const inferred: Record<string, EntryImageMimeType> = {
    heic: "image/heic",
    heif: "image/heif",
    jpeg: "image/jpeg",
    jpg: "image/jpeg",
    png: "image/png",
    webp: "image/webp",
  };

  return extension ? (inferred[extension] ?? null) : null;
}

export function isEntryUuid(value: unknown): value is string {
  return typeof value === "string" && uuidPattern.test(value);
}

function optionalPositiveInteger(value: unknown): number | null | undefined {
  if (value === null || value === undefined) {
    return null;
  }

  return typeof value === "number" && Number.isSafeInteger(value) && value > 0
    ? value
    : undefined;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function invalid(message: string) {
  return { message, success: false } as const;
}
