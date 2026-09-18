import "server-only";
import { getAuthenticatedContext, type Viewer } from "./inbox";
import { parsePlaceRows, type PlaceRecord } from "./place-record";

export type PlacesWorkspace = {
  inboxCount: number | undefined;
  loadError: string | null;
  places: PlaceRecord[];
  viewer: Viewer;
};

export async function getPlacesWorkspace(): Promise<PlacesWorkspace | null> {
  const context = await getAuthenticatedContext();
  if (!context) return null;

  const [places, inbox] = await Promise.all([
    context.client.rpc("places_workspace", { p_limit: 100, p_offset: 0 }),
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

  return {
    inboxCount: inbox.error ? undefined : (inbox.count ?? 0),
    loadError: null,
    places: rows,
    viewer: context.viewer,
  };
}

function unavailableWorkspace(
  viewer: Viewer,
  inboxCount: number | undefined,
): PlacesWorkspace {
  return {
    inboxCount,
    loadError: "MemoTrail could not load your Places. Refresh to try again.",
    places: [],
    viewer,
  };
}
