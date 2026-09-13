import "server-only";
import { createHash } from "node:crypto";
import type { SupabaseClient } from "@supabase/supabase-js";
import { mediaImage } from "@/lib/media/server";
import { AI_PHOTO_BYTES, AI_PHOTO_LIMIT, type AIImage } from "./image-input";

export async function suggestionPhotos(
  client: SupabaseClient,
  owner: string,
  entryID: string,
) {
  const deadline = Date.now() + 20_000;
  let timer: ReturnType<typeof setTimeout> | undefined;
  function checkDeadline() {
    if (Date.now() >= deadline) throw Error("Photo preparation timed out");
  }
  async function prepare() {
    const { data, error } = await client
      .from("attachments")
      .select("id")
      .eq("entry_id", entryID)
      .eq("owner_id", owner)
      .eq("bucket_id", "entry-media")
      .eq("variant", "original")
      .is("deleted_at", null)
      .order("created_at")
      .order("id")
      .limit(AI_PHOTO_LIMIT + 1);
    if (error || !data || data.length > AI_PHOTO_LIMIT)
      throw Error("Photo context unavailable");
    const images: AIImage[] = [];
    const fingerprint = createHash("sha256");
    for (const photo of data) {
      checkDeadline();
      // No public URLs or EXIF are given to the provider. Reuse the bounded, owner-checked renderer.
      const image = await mediaImage(
        { owner, id: photo.id, trash: false, expires: Date.now() + 60_000 },
        "thumbnail",
      );
      if (!image.size || image.size > AI_PHOTO_BYTES)
        throw Error("Photo context unavailable");
      const bytes = Buffer.from(await image.arrayBuffer());
      checkDeadline();
      fingerprint
        .update(photo.id)
        .update(createHash("sha256").update(bytes).digest());
      images.push({ mediaType: "image/webp", data: bytes.toString("base64") });
    }
    return {
      images,
      fingerprint: images.length ? fingerprint.digest("hex") : null,
    };
  }
  try {
    return await Promise.race([
      prepare(),
      new Promise<never>((_, reject) => {
        timer = setTimeout(
          () => reject(Error("Photo preparation timed out")),
          20_000,
        );
      }),
    ]);
  } finally {
    clearTimeout(timer);
  }
}
