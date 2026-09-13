import "server-only";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { createHash } from "node:crypto";
import { requireSupabasePublicConfig } from "@/lib/supabase/config";
import {
  MEDIA_MAX_BYTES,
  MEDIA_PIPELINE,
  type MediaGrant,
  type MediaVariant,
} from "./contracts";
import { renderPhoto } from "./render";
import { readPhotoMetadata } from "./metadata-worker";
type Source = {
  id: string;
  owner_id: string;
  entry_id: string;
  object_path: string;
  version: string;
  etag: string;
  byte_size: number;
  variants: {
    object_path: string;
    variant: MediaVariant;
    metadata: { pipeline: string; source_version: string; sha256: string };
  }[];
};
export class MediaError extends Error {
  constructor(public status: number) {
    super("Photo preview unavailable. The original is unchanged.");
  }
}
function adminClient() {
  if (!process.env.SUPABASE_SECRET_KEY) throw new MediaError(503);
  return createClient(
    requireSupabasePublicConfig().url,
    process.env.SUPABASE_SECRET_KEY,
    {
      auth: { persistSession: false, autoRefreshToken: false },
      global: {
        fetch: (input, init) =>
          fetch(input, {
            ...init,
            signal: init?.signal
              ? AbortSignal.any([init.signal, AbortSignal.timeout(20_000)])
              : AbortSignal.timeout(20_000),
          }),
      },
    },
  );
}
async function sourceFor(
  admin: SupabaseClient,
  grant: MediaGrant,
): Promise<Source> {
  const { data, error } = await admin.rpc("media_source", {
    p_owner_id: grant.owner,
    p_attachment_id: grant.id,
    p_allow_trash: grant.trash,
  });
  if (error) throw new MediaError(503);
  if (!data) throw new MediaError(404);
  return data;
}
function variantPath(source: Source, variant: MediaVariant) {
  return source.variants.find(
    (v) =>
      v.variant === variant &&
      v.metadata.pipeline === MEDIA_PIPELINE &&
      v.metadata.source_version === source.version,
  )?.object_path;
}
const pending = new Map<string, Promise<void>>();
let active = 0;
const queue: (() => void)[] = [];
async function limited<T>(run: () => Promise<T>): Promise<T> {
  if (active >= 2) {
    if (queue.length >= 48) throw new MediaError(503);
    await new Promise<void>((resolve, reject) => {
      const resume = () => {
        clearTimeout(timer);
        resolve();
      };
      const timer = setTimeout(() => {
        const index = queue.indexOf(resume);
        if (index >= 0) queue.splice(index, 1);
        reject(new MediaError(503));
      }, 10_000);
      queue.push(resume);
    });
  } else active++;
  try {
    return await run();
  } finally {
    const next = queue.shift();
    if (next) next();
    else active--;
  }
}
async function originalBytes(
  admin: SupabaseClient,
  source: Source,
): Promise<Buffer> {
  if (
    !source.version ||
    !source.etag ||
    !Number.isSafeInteger(source.byte_size) ||
    source.byte_size < 1 ||
    source.byte_size > MEDIA_MAX_BYTES
  )
    throw new MediaError(422);
  const { data, error } = await admin.storage
    .from("entry-media")
    .createSignedUrl(source.object_path, 60);
  if (error || !data) throw new MediaError(404);
  const response = await fetch(data.signedUrl, {
    cache: "no-store",
    redirect: "error",
    signal: AbortSignal.timeout(20_000),
  });
  const normalize = (value: string | null) =>
    value?.replace(/^W\//, "").replaceAll('"', "");
  if (
    !response.ok ||
    !response.body ||
    normalize(response.headers.get("etag")) !== normalize(source.etag)
  ) {
    await response.body?.cancel();
    throw new MediaError(409);
  }
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const part = await reader.read();
      if (part.done) break;
      size += part.value.length;
      if (size > MEDIA_MAX_BYTES || size > source.byte_size) {
        await reader.cancel();
        throw new MediaError(422);
      }
      chunks.push(part.value);
    }
  } finally {
    reader.releaseLock();
  }
  if (size !== source.byte_size) throw new MediaError(409);
  return Buffer.concat(chunks);
}
async function prepare(admin: SupabaseClient, source: Source) {
  const bytes = await originalBytes(admin, source);
  const hash = createHash("sha256").update(bytes).digest("hex");
  const rendered = await renderPhoto(bytes);
  const variants = [];
  for (const image of rendered) {
    const path = `${source.owner_id}/${source.entry_id}/derived/${source.id}/${MEDIA_PIPELINE}/${hash}/${image.variant}.webp`;
    // This path is a derived artifact, never an original. Identical concurrent jobs are safe to replace.
    const { error } = await admin.storage
      .from("entry-media")
      .upload(path, image.bytes, {
        contentType: "image/webp",
        upsert: true,
        cacheControl: "3600",
      });
    if (error) throw new MediaError(503);
    variants.push({
      object_path: path,
      variant: image.variant,
      byte_size: image.bytes.length,
      width: image.width,
      height: image.height,
      sha256: createHash("sha256").update(image.bytes).digest("hex"),
    });
  }
  const { data, error } = await admin.rpc("register_media_derivatives", {
    p_owner_id: source.owner_id,
    p_attachment_id: source.id,
    p_version: source.version,
    p_sha256: hash,
    p_variants: variants,
  });
  if (error || data !== true) throw new MediaError(409);
}
export async function mediaImage(
  grant: MediaGrant,
  variant: MediaVariant,
): Promise<Blob> {
  const admin = adminClient();
  let source = await sourceFor(admin, grant);
  let path = variantPath(source, variant);
  let image = path ? await verifiedDerivative(admin, source, path) : null;
  if (!image) {
    const key = `${grant.owner}:${grant.id}:${source.version}`;
    let work = pending.get(key);
    if (!work) {
      work = limited(() => prepare(admin, source));
      pending.set(key, work);
    }
    try {
      await work;
    } finally {
      if (pending.get(key) === work) pending.delete(key);
    }
    // Recheck visibility and source identity after conversion or a concurrent Trash/overwrite.
    source = await sourceFor(admin, grant);
    path = variantPath(source, variant);
    image = path ? await verifiedDerivative(admin, source, path) : null;
  }
  if (!image) throw new MediaError(409);
  const latest = await sourceFor(admin, grant);
  if (latest.version !== source.version) throw new MediaError(409);
  return image;
}
async function verifiedDerivative(
  admin: SupabaseClient,
  source: Source,
  path: string,
): Promise<Blob | null> {
  const { data, error } = await admin.storage
    .from("entry-media")
    .download(path);
  if (error || !data) return null;
  const expected = source.variants.find((v) => v.object_path === path)?.metadata
    .sha256;
  if (
    data.size > 8 * 1024 * 1024 ||
    createHash("sha256")
      .update(Buffer.from(await data.arrayBuffer()))
      .digest("hex") !== expected
  )
    return null;
  return data;
}

export async function photoMetadata(owner: string, id: string) {
  const admin = adminClient();
  const grant = { owner, id, expires: Date.now() + 60_000, trash: false };
  return limited(async () => {
    const source = await sourceFor(admin, grant);
    const metadata = await readPhotoMetadata(
      await originalBytes(admin, source),
    );
    const latest = await sourceFor(admin, grant);
    if (latest.version !== source.version) throw new MediaError(409);
    return { ...metadata, attachmentId: id, sourceVersion: source.version };
  });
}
