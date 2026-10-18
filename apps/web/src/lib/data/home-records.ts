import "server-only";
import { displayImageURLs } from "@/lib/media/urls";

import { getPrimaryEntryLocations } from "./entry-locations";
import { getAuthenticatedContext, type Viewer } from "./inbox";
import { loadTagOptions } from "./tag-options";
import { loadDefaultTimezone } from "./profile-timezone";
import {
  parseHomeRows,
  type HomeAttachment,
  type HomeRecord,
} from "./home-record";

export type HomesWorkspace = {
  // The Settings time zone, when the profile could be read.
  defaultTimezone?: string;
  homes: HomeRecord[];
  loadError: string | null;
  tagOptions: string[];
  viewer: Viewer;
};

export async function getHomesWorkspace(
  targetId?: string,
): Promise<HomesWorkspace | null> {
  const context = await getAuthenticatedContext();

  if (!context) {
    return null;
  }

  const [homes, tags, defaultTimezone] = await Promise.all([
    context.client.rpc("homes_workspace", { p_limit: 100, p_offset: 0 }),
    loadTagOptions(context.client, context.userId),
    loadDefaultTimezone(context.client, context.userId),
  ]);
  const rows = homes.error ? null : parseHomeRows(homes.data);

  if (!rows) {
    return unavailableWorkspace(context.viewer);
  }

  if (targetId && !rows.some((record) => record.id === targetId)) {
    for (let offset = 100; rows.length >= offset; offset += 100) {
      const page = await context.client.rpc("homes_workspace", {
        p_limit: 100,
        p_offset: offset,
      });
      const more = page.error ? null : parseHomeRows(page.data);
      if (!more) return unavailableWorkspace(context.viewer);
      rows.push(...more);
      if (more.length < 100 || more.some((record) => record.id === targetId))
        break;
    }
  }
  const visibleRows = targetId
    ? rows.filter((record) => record.id === targetId)
    : rows;

  const locations = await getPrimaryEntryLocations(
    context,
    visibleRows.map((row) => row.id),
  );
  if (!locations) {
    return unavailableWorkspace(context.viewer);
  }

  const attachments = visibleRows.flatMap((home) => home.attachments);
  const signedUrls = await signedImageUrls(context.client, attachments);

  return {
    homes: visibleRows.map((home) => ({
      ...home,
      location: locations.get(home.id) ?? null,
      attachments: home.attachments.map((attachment) => ({
        ...attachment,
        imageUrl: signedUrls.get(attachment.objectPath) ?? null,
      })),
    })),
    defaultTimezone,
    loadError: null,
    tagOptions: tags ?? [],
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

function unavailableWorkspace(viewer: Viewer): HomesWorkspace {
  return {
    homes: [],
    loadError: "MemoTrail could not load your Homes. Refresh to try again.",
    tagOptions: [],
    viewer,
  };
}
