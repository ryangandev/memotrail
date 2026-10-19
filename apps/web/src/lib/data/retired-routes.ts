import "server-only";

import { redirect } from "next/navigation";
import { validEntryID } from "@/lib/data/entry-detail";
import { getAuthenticatedContext } from "@/lib/data/inbox";

/**
 * Opens where an address from a retired section now lives. One valid Entry ID that still exists
 * opens that Entry's Item page, and every other address opens `fallback`.
 */
export async function redirectRetiredRecord(
  rest: string[],
  fallback: string,
): Promise<never> {
  const [id] = rest;
  if (rest.length === 1 && validEntryID(id)) {
    const context = await getAuthenticatedContext();
    if (context) {
      const { data } = await context.client.rpc("entry_detail", {
        p_entry_id: id,
      });
      if (data) redirect(`/items/${id}`);
    }
  }
  redirect(fallback);
}
