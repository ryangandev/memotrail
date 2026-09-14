import "server-only";

import { getAuthenticatedContext, type Viewer } from "./inbox";
import {
  parseOrganizationItems,
  type OrganizationItem,
  type OrganizationKind,
} from "./organization";

export type OrganizationWorkspace = {
  inboxCount: number | undefined;
  items: OrganizationItem[];
  loadError: string | null;
  page: number;
  query: string;
  totalCount: number;
  viewer: Viewer;
};

export async function getOrganizationWorkspace({
  kind,
  page = 1,
  query = "",
}: {
  kind: OrganizationKind;
  page?: number;
  query?: string;
}): Promise<OrganizationWorkspace | null> {
  const context = await getAuthenticatedContext();
  if (!context) return null;

  const [organization, inbox] = await Promise.all([
    context.client.rpc("organization_workspace", {
      p_kind: kind,
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
  const parsed = organization.error
    ? null
    : parseOrganizationItems(organization.data);
  const items = (parsed ?? []).map(normalizeCounts);

  return {
    inboxCount: inbox.error ? undefined : (inbox.count ?? 0),
    items,
    loadError: parsed
      ? null
      : `MemoTrail could not load your ${kind === "tag" ? "tags" : "Collections"}. Refresh to try again.`,
    page,
    query,
    totalCount: items[0]?.total_count ?? 0,
    viewer: context.viewer,
  };
}

export function normalizeCounts(item: OrganizationItem): OrganizationItem {
  return {
    ...item,
    entry_count: Number(item.entry_count),
    total_count: Number(item.total_count),
  };
}
