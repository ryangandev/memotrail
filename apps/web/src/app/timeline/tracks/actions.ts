"use server";
import { revalidatePath } from "next/cache";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import { validTrackInput, type TrackInput } from "@/lib/data/tracks";
export async function saveTrack(input: TrackInput): Promise<string | null> {
  if (!input || !validTrackInput(input))
    return "Use a name up to 100 characters and a whole-number order between -1,000,000 and 1,000,000.";
  const context = await getAuthenticatedContext();
  if (!context) return "Sign in again to manage tracks.";
  const { data, error } = await context.client.rpc("save_timeline_track", {
    p_name: input.name.trim(),
    p_sort_order: input.order,
    p_is_hidden: input.hidden,
    p_track_id: input.id,
    p_expected_revision: input.revision,
  });
  if (error?.code === "23505")
    return "A track with this name already exists, including hidden tracks.";
  if (error)
    return "Could not save this track. Your edits are still here to retry.";
  if (!data)
    return "This track changed on another device. Reload tracks before editing again.";
  revalidatePath("/timeline", "layout");
  return null;
}
