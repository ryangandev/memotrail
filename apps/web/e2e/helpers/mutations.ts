import type { SupabaseClient } from "@supabase/supabase-js";
import { expect } from "@playwright/test";

// A second-device write must retry an optimistic conflict with a fresh revision.
// An empty successful response is a conflict, not proof that the write happened.
export async function saveAtCurrentRevision(
  client: SupabaseClient,
  rpc: string,
  entryID: string,
  parameters: Record<string, unknown>,
) {
  for (let attempt = 0; attempt < 3; attempt += 1) {
    const current = await client
      .from("entries")
      .select("revision")
      .eq("id", entryID)
      .single();
    expect(current.error).toBeNull();
    const saved = await client.rpc(rpc, {
      ...parameters,
      p_entry_id: entryID,
      p_expected_revision: current.data!.revision,
    });
    expect(saved.error).toBeNull();
    if (saved.data?.length) {
      expect(saved.data).toHaveLength(1);
      return saved.data;
    }
  }
  throw new Error("The second-device mutation remained in conflict.");
}
