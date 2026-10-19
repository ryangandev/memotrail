import { Upload } from "tus-js-client";
import { createClient } from "@/lib/supabase/client";
import { requireSupabasePublicConfig } from "@/lib/supabase/config";
import { stagingBucket } from "./bucket";

/** Supabase Storage takes resumable uploads in chunks of exactly this size. */
const chunkSize = 6 * 1024 * 1024;

export class UploadFailedError extends Error {
  constructor(
    message: string,
    public tooLarge = false,
  ) {
    super(message);
  }
}

/**
 * Sends the ZIP straight to the private staging bucket in resumable chunks, as the signed-in
 * person. A closed tab or a lost connection continues from the last chunk when the same file is
 * chosen again.
 */
export function uploadStagedZip(input: {
  file: File;
  objectName: string;
  onProgress: (sent: number, total: number) => void;
  signal: AbortSignal;
}): Promise<void> {
  const { publishableKey, url } = requireSupabasePublicConfig();
  const supabase = createClient();
  return new Promise((resolve, reject) => {
    const upload = new Upload(input.file, {
      chunkSize,
      endpoint: `${url}/storage/v1/upload/resumable`,
      headers: { apikey: publishableKey, "x-upsert": "true" },
      metadata: {
        bucketName: stagingBucket,
        cacheControl: "3600",
        contentType: "application/zip",
        objectName: input.objectName,
      },
      onBeforeRequest: async (request) => {
        // A long upload outlives one access token.
        const { data } = await supabase.auth.getSession();
        if (data.session)
          request.setHeader(
            "Authorization",
            `Bearer ${data.session.access_token}`,
          );
      },
      onError: (error) => {
        const status = (
          error as { originalResponse?: { getStatus(): number } }
        ).originalResponse?.getStatus();
        reject(
          new UploadFailedError(
            status === 413
              ? "The file is larger than this MemoTrail allows."
              : "The upload was interrupted. Choose the same file to continue.",
            status === 413,
          ),
        );
      },
      onProgress: (sent, total) => input.onProgress(sent, total),
      onSuccess: () => resolve(),
      removeFingerprintOnSuccess: true,
      retryDelays: [0, 2000, 5000, 10_000, 20_000],
      uploadDataDuringCreation: true,
    });
    input.signal.addEventListener("abort", () => {
      void upload.abort();
      reject(new DOMException("Upload cancelled", "AbortError"));
    });
    void upload.findPreviousUploads().then(
      (previous) => {
        if (previous[0]) upload.resumeFromPreviousUpload(previous[0]);
        upload.start();
      },
      () => upload.start(),
    );
  });
}
