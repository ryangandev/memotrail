import { createClient } from "@/lib/supabase/client";
import {
  createFirstTimeObjectPath,
  inferFirstTimeImageMimeType,
  type FirstTimeAttachmentInput,
} from "@/lib/data/first-time-input";

type RegisterPhoto = (
  input: FirstTimeAttachmentInput,
) => Promise<{ status: string }>;
type Operations = {
  upload: (input: FirstTimeAttachmentInput, file: File) => Promise<boolean>;
  register: RegisterPhoto;
};

/** A selected immutable File keeps its identity across retries in the open editor. */
export function createPhotoUploadBatch() {
  const identities = new WeakMap<
    File,
    Map<string, { id: string; uploaded: boolean }>
  >();
  return async (
    ownerId: string,
    entryId: string,
    files: File[],
    operations: Operations,
  ) => {
    const failed: File[] = [];
    for (const file of files) {
      let scopes = identities.get(file);
      if (!scopes) {
        scopes = new Map();
        identities.set(file, scopes);
      }
      const scope = `${ownerId}:${entryId}`;
      let state = scopes.get(scope);
      if (!state) {
        state = { id: crypto.randomUUID(), uploaded: false };
        scopes.set(scope, state);
      }
      const mimeType = inferFirstTimeImageMimeType(file.name, file.type);
      const objectPath = mimeType
        ? createFirstTimeObjectPath(ownerId, entryId, state.id, mimeType)
        : null;
      if (!mimeType || !objectPath) {
        failed.push(file);
        continue;
      }
      const input: FirstTimeAttachmentInput = {
        attachmentId: state.id,
        entryId,
        objectPath,
        mimeType,
        byteSize: file.size,
        originalFilename: file.name || null,
        pixelHeight: null,
        pixelWidth: null,
      };
      try {
        if (!state.uploaded) {
          try {
            state.uploaded = await operations.upload(input, file);
          } catch {
            /* An interrupted upload may already exist. Registration checks it. */
          }
        }
        const result = await operations.register(input);
        if (result.status === "saved") state.uploaded = true;
        else failed.push(file);
      } catch {
        failed.push(file);
      }
    }
    return failed;
  };
}

const batch = createPhotoUploadBatch();
export async function uploadEntryPhotos(
  ownerId: string,
  entryId: string,
  photos: File[],
  register: RegisterPhoto,
) {
  if (photos.length === 0) return [];
  const client = createClient();
  return batch(ownerId, entryId, photos, {
    register,
    upload: async (input, file) => {
      const result = await client.storage
        .from("entry-media")
        .upload(input.objectPath, file, {
          cacheControl: "3600",
          contentType: input.mimeType,
          upsert: false,
        });
      // A duplicate or transport error is not evidence that the original is absent.
      // The owner-scoped idempotent registration remains the source of truth.
      return !result.error;
    },
  });
}
