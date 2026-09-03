import "server-only";

import { getAuthenticatedContext, type Viewer } from "./inbox";
import {
  parseHomePlaceOptions,
  parseHomeRows,
  type HomeAttachment,
  type HomePlaceOption,
  type HomeRecord,
} from "./home-record";

export type HomesWorkspace = {
  collectionOptions: string[];
  homes: HomeRecord[];
  inboxCount: number | undefined;
  loadError: string | null;
  placeOptions: HomePlaceOption[];
  tagOptions: string[];
  viewer: Viewer;
};

type NameRow = { name: string };

export async function getHomesWorkspace(): Promise<HomesWorkspace | null> {
  const context = await getAuthenticatedContext();

  if (!context) {
    return null;
  }

  const [homes, places, collections, tags, inbox] = await Promise.all([
    context.client.rpc("homes_workspace", { p_limit: 100, p_offset: 0 }),
    context.client
      .from("places")
      .select("id,name,address,city,region,country,latitude,longitude,notes")
      .eq("owner_id", context.userId)
      .order("name"),
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

  const attachments = rows.flatMap((home) => home.attachments);
  const signedUrls = await signedImageUrls(context.client, attachments);
  const placeOptions = places.error
    ? []
    : (parseHomePlaceOptions(places.data) ?? []);

  return {
    collectionOptions: collections.error
      ? []
      : (collections.data ?? []).map((item) => item.name),
    homes: rows.map((home) => ({
      ...home,
      attachments: home.attachments.map((attachment) => ({
        ...attachment,
        imageUrl: signedUrls.get(attachment.objectPath) ?? null,
      })),
    })),
    inboxCount: inbox.error ? undefined : (inbox.count ?? 0),
    loadError: null,
    placeOptions,
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
  const urls = new Map<string, string>();

  if (paths.length === 0) {
    return urls;
  }

  const { data, error } = await client.storage
    .from("entry-media")
    .createSignedUrls(paths, 60 * 60);

  if (error) {
    return urls;
  }

  for (const item of data ?? []) {
    if (item.path && item.signedUrl) {
      urls.set(item.path, item.signedUrl);
    }
  }

  return urls;
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
    placeOptions: [],
    tagOptions: [],
    viewer,
  };
}
