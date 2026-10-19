import { redirect } from "next/navigation";
import { validEntryID } from "@/lib/data/entry-detail";
import { getAuthenticatedContext } from "@/lib/data/inbox";

export const dynamic = "force-dynamic";

// Someday is retired: an item is now an Entry tagged "someday". An old item
// address opens that Entry's Item page while it exists, and every other old
// address opens Library.
export default async function RetiredSomedayPage({
  params,
}: {
  params: Promise<{ rest?: string[] }>;
}) {
  const { rest = [] } = await params;
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
  redirect("/library");
}
