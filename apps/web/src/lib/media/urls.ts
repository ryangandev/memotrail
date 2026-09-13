import "server-only";
import type { SupabaseClient } from "@supabase/supabase-js";
import { signMediaGrant } from "./contracts";

export async function displayImageURLs(
  client: SupabaseClient,
  paths: string[],
  trash = false,
): Promise<Map<string, string>> {
  const result = new Map<string, string>();
  const secret = process.env.SUPABASE_SECRET_KEY;
  const base = process.env.NEXT_PUBLIC_APP_URL;
  if (!secret || !base) return result;
  const unique = [...new Set(paths)];
  for (let index = 0; index < unique.length; index += 100) {
    // This query runs as the verified caller, not the service role.
    const { data, error } = await client
      .from("attachments")
      .select("id,owner_id,object_path")
      .eq("variant", "original")
      .eq("bucket_id", "entry-media")
      .in("object_path", unique.slice(index, index + 100));
    if (error) continue;
    for (const row of data ?? []) {
      const token = signMediaGrant(
        {
          owner: row.owner_id,
          id: row.id,
          expires: Date.now() + 3_600_000,
          trash,
        },
        secret,
      );
      const url = new URL("/api/media/image", base);
      url.searchParams.set("token", token);
      result.set(row.object_path, url.toString());
    }
  }
  return result;
}
