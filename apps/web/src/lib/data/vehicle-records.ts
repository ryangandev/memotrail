import "server-only";
import { displayImageURLs } from "@/lib/media/urls";

import { getAuthenticatedContext, type Viewer } from "./inbox";
import { getPrimaryEntryLocations } from "./entry-locations";
import {
  parseVehicleRows,
  type VehicleAttachment,
  type VehicleRecord,
} from "./vehicle-record";

export type VehiclesWorkspace = {
  loadError: string | null;
  tagOptions: string[];
  vehicles: VehicleRecord[];
  viewer: Viewer;
};

type NameRow = { name: string };

export async function getVehiclesWorkspace(
  targetId?: string,
): Promise<VehiclesWorkspace | null> {
  const context = await getAuthenticatedContext();
  if (!context) return null;

  const [vehicles, tags] = await Promise.all([
    context.client.rpc("vehicles_workspace", { p_limit: 100, p_offset: 0 }),
    context.client
      .from("tags")
      .select("name")
      .eq("owner_id", context.userId)
      .order("name")
      .returns<NameRow[]>(),
  ]);
  const rows = vehicles.error ? null : parseVehicleRows(vehicles.data);
  if (!rows) {
    return unavailableWorkspace(context.viewer);
  }

  if (targetId && !rows.some((record) => record.id === targetId)) {
    for (let offset = 100; rows.length >= offset; offset += 100) {
      const page = await context.client.rpc("vehicles_workspace", {
        p_limit: 100,
        p_offset: offset,
      });
      const more = page.error ? null : parseVehicleRows(page.data);
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

  const attachments = visibleRows.flatMap((vehicle) => vehicle.attachments);
  const signedUrls = await signedImageUrls(context.client, attachments);

  return {
    loadError: null,
    tagOptions: tags.error ? [] : (tags.data ?? []).map((item) => item.name),
    vehicles: visibleRows.map((vehicle) => ({
      ...vehicle,
      location: locations.get(vehicle.id) ?? null,
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

function unavailableWorkspace(viewer: Viewer): VehiclesWorkspace {
  return {
    loadError: "MemoTrail could not load your Vehicles. Refresh to try again.",
    tagOptions: [],
    vehicles: [],
    viewer,
  };
}
