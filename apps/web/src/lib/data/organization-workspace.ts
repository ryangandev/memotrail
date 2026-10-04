import "server-only";

import { getAuthenticatedContext, type Viewer } from "./inbox";
import { parseTagItems, type TagItem } from "./organization";

export type TagsWorkspace = {
  inboxCount: number | undefined;
  items: TagItem[];
  loadError: string | null;
  page: number;
  query: string;
  totalCount: number;
  viewer: Viewer;
};

export async function getTagsWorkspace({
  page = 1,
  query = "",
}: {
  page?: number;
  query?: string;
}): Promise<TagsWorkspace | null> {
  const context = await getAuthenticatedContext();
  if (!context) return null;

  const [tags, inbox] = await Promise.all([
    context.client.rpc("tags_workspace", {
      p_limit: 50,
      p_offset: (page - 1) * 50,
      p_query: query,
    }),
    context.client
      .from("entries")
      .select("id", { count: "exact", head: true })
      .eq("owner_id", context.userId)
      .eq("inbox_status", "unreviewed")
      .is("deleted_at", null),
  ]);
  const parsed = tags.error ? null : parseTagItems(tags.data);
  const items = (parsed ?? []).map(normalizeCounts);

  return {
    inboxCount: inbox.error ? undefined : (inbox.count ?? 0),
    items,
    loadError: parsed
      ? null
      : "MemoTrail could not load your tags. Refresh to try again.",
    page,
    query,
    totalCount: items[0]?.total_count ?? 0,
    viewer: context.viewer,
  };
}

function normalizeCounts(item: TagItem): TagItem {
  return {
    ...item,
    entry_count: Number(item.entry_count),
    total_count: Number(item.total_count),
  };
}
