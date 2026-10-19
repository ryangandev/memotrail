import type { SupabaseClient } from "@supabase/supabase-js";
import { importMaxZipBytes } from "./limits";
import { ImportError, ZipArchive, looksLikeZip, type RangeSource } from "./zip";

export const stagingBucket = "import-staging";

type Fetch = typeof fetch;

const attempts = 3;

async function withRetry<T>(task: () => Promise<T>): Promise<T> {
  let last: unknown;
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    try {
      return await task();
    } catch (error) {
      last = error;
      if (error instanceof ImportError) throw error;
      await new Promise((resolve) => setTimeout(resolve, 200 * 2 ** attempt));
    }
  }
  throw last;
}

/** Reads a Storage object by byte ranges through a short-lived signed address. */
export async function httpRangeSource(
  url: string,
  fetchImpl: Fetch = fetch,
): Promise<RangeSource> {
  // One byte tells the whole size, in Content-Range.
  const size = await withRetry(async () => {
    const response = await fetchImpl(url, { headers: { Range: "bytes=0-0" } });
    if (response.status === 404 || response.status === 400)
      throw new ImportError("storage_unavailable");
    if (!response.ok) throw new Error(`storage ${response.status}`);
    await response.arrayBuffer();
    const total = /\/(\d+)$/.exec(response.headers.get("content-range") ?? "")?.[1];
    const length = Number(total ?? response.headers.get("content-length"));
    if (!Number.isSafeInteger(length) || length < 1)
      throw new ImportError("storage_unavailable");
    return length;
  });
  return {
    read: (start, end) =>
      withRetry(async () => {
        const response = await fetchImpl(url, {
          headers: { Range: `bytes=${start}-${end - 1}` },
        });
        if (!response.ok) throw new Error(`storage ${response.status}`);
        const bytes = Buffer.from(await response.arrayBuffer());
        // A server that ignores the range sends everything.
        return response.status === 206 ? bytes : bytes.subarray(start, end);
      }),
    size,
  };
}

/** Opens the staged ZIP of a job without downloading it whole. */
export async function openStagedArchive(
  client: SupabaseClient,
  stagingPath: string,
  options: { maxBytes?: number; fetchImpl?: Fetch } = {},
): Promise<{ archive: ZipArchive; size: number }> {
  const maxBytes = options.maxBytes ?? importMaxZipBytes();
  const signed = await client.storage
    .from(stagingBucket)
    .createSignedUrl(stagingPath, 3600);
  if (signed.error || !signed.data?.signedUrl)
    throw new ImportError("storage_unavailable");
  const source = await httpRangeSource(signed.data.signedUrl, options.fetchImpl);
  if (source.size > maxBytes) throw new ImportError("too_large");
  const head = await source.read(0, Math.min(4, source.size));
  if (!looksLikeZip(head)) throw new ImportError("unsupported_archive");
  return { archive: await ZipArchive.open(source), size: source.size };
}

/** Removes staged ZIPs through the Storage API. Returns the paths that were removed. */
export async function removeStagedFiles(
  client: SupabaseClient,
  paths: string[],
): Promise<string[]> {
  if (paths.length === 0) return [];
  const { data, error } = await client.storage.from(stagingBucket).remove(paths);
  if (error) return [];
  // Removing a file that is already gone is not an error, so every path counts as removed.
  void data;
  return paths;
}
