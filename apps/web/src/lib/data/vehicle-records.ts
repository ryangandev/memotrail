import "server-only";
import { displayImageURLs } from "@/lib/media/urls";

import { getAuthenticatedContext, type Viewer } from "./inbox";
import {
  parseVehicleRows,
  type VehicleAttachment,
  type VehicleRecord,
} from "./vehicle-record";

export type VehiclesWorkspace = {
  collectionOptions: string[];
  inboxCount: number | undefined;
  loadError: string | null;
  tagOptions: string[];
  vehicles: VehicleRecord[];
  viewer: Viewer;
};

type NameRow = { name: string };

export async function getVehiclesWorkspace(): Promise<VehiclesWorkspace | null> {
  const context = await getAuthenticatedContext();
  if (!context) return null;

  const [vehicles, collections, tags, inbox] = await Promise.all([
    context.client.rpc("vehicles_workspace", { p_limit: 100, p_offset: 0 }),
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
  const rows = vehicles.error ? null : parseVehicleRows(vehicles.data);
  if (!rows) {
    return unavailableWorkspace(context.viewer, inbox.count ?? undefined);
  }

  const attachments = rows.flatMap((vehicle) => vehicle.attachments);
  const signedUrls = await signedImageUrls(context.client, attachments);

  return {
    collectionOptions: collections.error
      ? []
      : (collections.data ?? []).map((item) => item.name),
    inboxCount: inbox.error ? undefined : (inbox.count ?? 0),
    loadError: null,
    tagOptions: tags.error ? [] : (tags.data ?? []).map((item) => item.name),
    vehicles: rows.map((vehicle) => ({
      ...vehicle,
      attachments: vehicle.attachments.map((attachment) => ({
        ...attachment,
        imageUrl: signedUrls.get(attachment.objectPath) ?? null,
      })),
    })),
    viewer: context.viewer,
  };
}

async function signedImageUrls(
  client: NonNullable<
    Awaited<ReturnType<typeof getAuthenticatedContext>>
  >["client"],
  attachments: VehicleAttachment[],
) {
  const paths = [...new Set(attachments.map((item) => item.objectPath))];
  return displayImageURLs(client, paths);
}

function unavailableWorkspace(
  viewer: Viewer,
  inboxCount: number | undefined,
): VehiclesWorkspace {
  return {
    collectionOptions: [],
    inboxCount,
    loadError: "MemoTrail could not load your Vehicles. Refresh to try again.",
    tagOptions: [],
    vehicles: [],
    viewer,
  };
}
