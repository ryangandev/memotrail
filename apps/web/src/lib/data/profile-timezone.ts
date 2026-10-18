import type { SupabaseClient } from "@supabase/supabase-js";
import { storedProfileTimezone } from "./profile-input";

// The Settings time zone that date editors treat as the default. Without a readable
// profile there is no default, and editors show every time zone in full.
export async function loadDefaultTimezone(
  client: SupabaseClient,
  userId: string,
): Promise<string | undefined> {
  const { data, error } = await client
    .from("profiles")
    .select("timezone")
    .eq("user_id", userId)
    .single();
  const stored = storedProfileTimezone(error ? null : data);
  return stored.available ? stored.timezone : undefined;
}
