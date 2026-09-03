import "server-only";

import { getAuthenticatedContext, type Viewer } from "./inbox";
import {
  parsePlaceLinkOptions,
  parsePlaceRows,
  type PlaceAttachment,
  type PlaceLinkOption,
  type PlaceRecord,
} from "./place-record";

export type PlacesWorkspace = {
  inboxCount: number | undefined;
  linkOptions: PlaceLinkOption[];
  loadError: string | null;
  places: PlaceRecord[];
  viewer: Viewer;
};

export async function getPlacesWorkspace(): Promise<PlacesWorkspace | null> {
  const context = await getAuthenticatedContext();
  if (!context) return null;

  const [places, links, inbox] = await Promise.all([
    context.client.rpc("places_workspace", { p_limit: 100, p_offset: 0 }),
    context.client
      .from("entries")
      .select("id,title,body,entry_type,updated_at")
      .eq("owner_id", context.userId)
      .is("deleted_at", null)
      .order("updated_at", { ascending: false })
      .limit(200),
    context.client
      .from("entries")
      .select("id", { count: "exact", head: true })
      .eq("owner_id", context.userId)
      .eq("inbox_status", "unreviewed")
      .is("deleted_at", null),
  ]);

  const rows = places.error ? null : parsePlaceRows(places.data);
  if (!rows) {
    return unavailableWorkspace(context.viewer, inbox.count ?? undefined);
  }

  const attachments = rows.flatMap((place) =>
    place.linkedEntries.flatMap((entry) => entry.attachments),
  );
  const signedUrls = await signedImageUrls(context.client, attachments);
  const linkOptions = links.error
    ? []
    : (parsePlaceLinkOptions(links.data) ?? []);

  return {
    inboxCount: inbox.error ? undefined : (inbox.count ?? 0),
    linkOptions,
    loadError: null,
    places: rows.map((place) => ({
      ...place,
      linkedEntries: place.linkedEntries.map((entry) => ({
        ...entry,
        attachments: entry.attachments.map((attachment) => ({
          ...attachment,
          imageUrl: signedUrls.get(attachment.objectPath) ?? null,
        })),
      })),
    })),
    viewer: context.viewer,
  };
}

async function signedImageUrls(
  client: NonNullable<
    Awaited<ReturnType<typeof getAuthenticatedContext>>
  >["client"],
  attachments: PlaceAttachment[],
) {
  const paths = [...new Set(attachments.map((item) => item.objectPath))];
  const urls = new Map<string, string>();
  if (paths.length === 0) return urls;

  const { data, error } = await client.storage
    .from("entry-media")
    .createSignedUrls(paths, 60 * 60);
  if (error) return urls;
  for (const item of data ?? []) {
    if (item.path && item.signedUrl) urls.set(item.path, item.signedUrl);
  }
  return urls;
}

function unavailableWorkspace(
  viewer: Viewer,
  inboxCount: number | undefined,
): PlacesWorkspace {
  return {
    inboxCount,
    linkOptions: [],
    loadError: "MemoTrail could not load your Places. Refresh to try again.",
    places: [],
    viewer,
  };
}
