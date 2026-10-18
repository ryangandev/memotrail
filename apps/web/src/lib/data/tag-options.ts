import type { SupabaseClient } from "@supabase/supabase-js";

type TagUsageRow = { name: string; entry_tags: { count: number }[] };

// The tag choices every Entry editor offers, most used first, so the editor can suggest
// the tags people actually reuse. Entries in Trash do not count toward a tag's use.
export async function loadTagOptions(
  client: SupabaseClient,
  ownerId: string,
): Promise<string[] | null> {
  const { data, error } = await client
    .from("tags")
    .select("name, entry_tags(count, entries!inner())")
    .eq("owner_id", ownerId)
    .is("entry_tags.entries.deleted_at", null)
    .returns<TagUsageRow[]>();
  return error || !data ? null : tagOptionsByUse(data);
}

export function tagOptionsByUse(rows: TagUsageRow[]) {
  return rows
    .map((row) => ({ count: row.entry_tags[0]?.count ?? 0, name: row.name }))
    .sort(
      (left, right) =>
        right.count - left.count ||
        left.name.localeCompare(right.name, undefined, {
          sensitivity: "base",
        }),
    )
    .map((tag) => tag.name);
}
