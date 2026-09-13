import type { SupabaseClient } from "@supabase/supabase-js";

/** Only photo-only revisions commute with writing. Never adopt an unseen text edit. */
export async function writingRevision(
  client: SupabaseClient,
  entryId: string | null,
  revision: number | null,
) {
  if (!entryId || revision === null) return revision;
  try {
    const { data, error } = await client.rpc("entry_writing_revision", {
      p_entry_id: entryId,
      p_expected_revision: revision,
    });
    return !error && Number.isSafeInteger(data) && data >= revision
      ? (data as number)
      : revision;
  } catch {
    // The original optimistic guard still protects writes during a lookup failure.
    return revision;
  }
}
