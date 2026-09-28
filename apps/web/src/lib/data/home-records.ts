import "server-only";
import { displayImageURLs } from "@/lib/media/urls";

import { getAuthenticatedContext, type Viewer } from "./inbox";
import {
  parseHomeRows,
  type HomeAttachment,
  type HomeRecord,
} from "./home-record";

export type HomesWorkspace = {
  collectionOptions: string[];
  homes: HomeRecord[];
  inboxCount: number | undefined;
  loadError: string | null;
  tagOptions: string[];
  viewer: Viewer;
};

type NameRow = { name: string };

export async function getHomesWorkspace(
  targetId?: string,
): Promise<HomesWorkspace | null> {
  const context = await getAuthenticatedContext();

  if (!context) {
    return null;
  }

  const [homes, collections, tags, inbox] = await Promise.all([
    context.client.rpc("homes_workspace", { p_limit: 100, p_offset: 0 }),
    context.client
      .from("collections")
      .select("name")
      .eq("owner_id", context.userId)
      .is("archived_at", null)
      .order("name")
      .returns<NameRow[]>(),
    context.client
      .from("tags")
      .select("name")
      .eq("owner_id", context.userId)
      .order("name")
      .returns<NameRow[]>(),
    context.client
      .from("entries")
      .select("id", { count: "exact", head: true })
      .eq("owner_id", context.userId)
      .eq("inbox_status", "unreviewed")
      .is("deleted_at", null),
  ]);
  const rows = homes.error ? null : parseHomeRows(homes.data);

  if (!rows) {
    return unavailableWorkspace(context.viewer, inbox.count ?? undefined);
  }

  if (targetId && !rows.some((record) => record.id === targetId)) {
    for (let offset = 100; rows.length >= offset; offset += 100) {
      const page = await context.client.rpc("homes_workspace", {
        p_limit: 100,
        p_offset: offset,
      });
      const more = page.error ? null : parseHomeRows(page.data);
      if (!more)
        return unavailableWorkspace(context.viewer, inbox.count ?? undefined);
      rows.push(...more);
      if (more.length < 100 || more.some((record) => record.id === targetId))
        break;
    }
  }
  const visibleRows = targetId
    ? rows.filter((record) => record.id === targetId)
    : rows;

  const attachments = visibleRows.flatMap((home) => home.attachments);
  const signedUrls = await signedImageUrls(context.client, attachments);

  return {
    collectionOptions: collections.error
      ? []
      : (collections.data ?? []).map((item) => item.name),
    homes: visibleRows.map((home) => ({
      ...home,
      attachments: home.attachments.map((attachment) => ({
        ...attachment,
        imageUrl: signedUrls.get(attachment.objectPath) ?? null,
      })),
    })),
    inboxCount: inbox.error ? undefined : (inbox.count ?? 0),
    loadError: null,
    tagOptions: tags.error ? [] : (tags.data ?? []).map((item) => item.name),
    viewer: context.viewer,
  };
}

async function signedImageUrls(
  client: NonNullable<
    Awaited<ReturnType<typeof getAuthenticatedContext>>
  >["client"],
  attachments: HomeAttachment[],
) {
  const paths = [...new Set(attachments.map((item) => item.objectPath))];
  return displayImageURLs(client, paths);
}

function unavailableWorkspace(
  viewer: Viewer,
  inboxCount: number | undefined,
): HomesWorkspace {
  return {
    collectionOptions: [],
    homes: [],
    inboxCount,
    loadError: "MemoTrail could not load your Homes. Refresh to try again.",
    tagOptions: [],
    viewer,
  };
}
