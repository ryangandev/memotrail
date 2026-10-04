import "server-only";

import { getAuthenticatedContext } from "@/lib/data/inbox";
import { locationDisplayLabel } from "@/lib/locations/location";
import {
  isWikiItemKind,
  wikiEntryHref,
  type WikiItemKind,
} from "@/lib/data/wiki-item";

export type LocationMapItem = {
  id: string;
  locationId: string;
  title: string;
  kind: WikiItemKind;
  subtype: string;
  occurredAt: string | null;
  latitude: number;
  longitude: number;
  address: string;
  city: string | null;
  region: string | null;
  country: string | null;
  href: string;
};

type LinkRow = { entry_id: string; location_id: string };
type EntryRow = {
  id: string;
  title: string;
  item_kind: string;
  item_subtype: string;
  occurred_start: string | null;
};
type LocationRow = {
  id: string;
  latitude: number | null;
  longitude: number | null;
  formatted_address: string | null;
  address: string | null;
  city: string | null;
  region: string | null;
  country: string | null;
};

export async function getLocationMapWorkspace() {
  const context = await getAuthenticatedContext();
  if (!context) return null;

  const links: LinkRow[] = [];
  let truncated = false;
  for (let offset = 0; offset <= 5000; offset += 250) {
    const { data, error } = await context.client
      .from("entry_locations")
      .select("entry_id,location_id")
      .eq("owner_id", context.userId)
      .order("created_at", { ascending: false })
      .order("entry_id")
      .range(offset, offset + 249)
      .returns<LinkRow[]>();
    if (error)
      return {
        items: [],
        loadError: "The map could not load your Locations.",
        truncated: false,
      };
    if (offset === 5000) {
      truncated = Boolean(data?.length);
      break;
    }
    links.push(...(data ?? []));
    if ((data?.length ?? 0) < 250) break;
  }

  const items: LocationMapItem[] = [];
  const included = new Set<string>();
  for (let offset = 0; offset < links.length; offset += 250) {
    const batch = links.slice(offset, offset + 250);
    const entryIds = [...new Set(batch.map((link) => link.entry_id))];
    const locationIds = [...new Set(batch.map((link) => link.location_id))];
    const [entriesResult, locationsResult] = await Promise.all([
      context.client
        .from("entries")
        .select("id,title,item_kind,item_subtype,occurred_start")
        .eq("owner_id", context.userId)
        .is("deleted_at", null)
        .in("id", entryIds)
        .returns<EntryRow[]>(),
      context.client
        .from("locations")
        .select(
          "id,latitude,longitude,formatted_address,address,city,region,country",
        )
        .eq("owner_id", context.userId)
        .in("id", locationIds)
        .returns<LocationRow[]>(),
    ]);
    if (entriesResult.error || locationsResult.error) {
      return {
        items: [],
        loadError: "The map could not load your Locations.",
        truncated: false,
      };
    }
    const entries = new Map(
      (entriesResult.data ?? []).map((entry) => [entry.id, entry]),
    );
    const locations = new Map(
      (locationsResult.data ?? []).map((location) => [location.id, location]),
    );
    for (const link of batch) {
      const entry = entries.get(link.entry_id);
      const location = locations.get(link.location_id);
      if (
        !entry ||
        !location ||
        !isWikiItemKind(entry.item_kind) ||
        location.latitude === null ||
        location.longitude === null
      )
        continue;
      const pair = `${entry.id}:${location.id}`;
      if (included.has(pair)) continue;
      included.add(pair);
      items.push({
        id: entry.id,
        locationId: location.id,
        title: entry.title,
        kind: entry.item_kind,
        subtype: entry.item_subtype,
        occurredAt: entry.occurred_start,
        latitude: location.latitude,
        longitude: location.longitude,
        address: locationDisplayLabel({
          formattedAddress: location.formatted_address,
          address: location.address,
          city: location.city,
          region: location.region,
          country: location.country,
          latitude: location.latitude,
          longitude: location.longitude,
        }),
        city: location.city,
        region: location.region,
        country: location.country,
        href: wikiEntryHref({
          id: entry.id,
          itemKind: entry.item_kind,
          itemSubtype: entry.item_subtype,
        }),
      });
    }
  }

  return { items, loadError: null, truncated };
}
