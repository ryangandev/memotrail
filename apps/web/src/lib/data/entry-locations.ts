import "server-only";

import {
  existingLocationFromRow,
  type ExistingLocation,
} from "@/lib/locations/location";
import { getAuthenticatedContext } from "./inbox";

type Context = NonNullable<Awaited<ReturnType<typeof getAuthenticatedContext>>>;
type EntryLocationRow = { entry_id: string; location: unknown };

export async function getPrimaryEntryLocations(
  context: Context,
  entryIds: string[],
): Promise<Map<string, ExistingLocation> | null> {
  if (entryIds.length === 0) return new Map();

  const { data, error } = await context.client
    .from("entry_locations")
    .select(
      "entry_id,location:locations!entry_locations_location_id_owner_id_fkey(id,revision,formatted_address,address,city,region,postal_code,country,country_code,latitude,longitude,timezone_id,result_type)",
    )
    .eq("owner_id", context.userId)
    .eq("relationship", "primary")
    .in("entry_id", entryIds)
    .returns<EntryLocationRow[]>();

  if (error) return null;
  const locations = new Map<string, ExistingLocation>();
  for (const row of data ?? []) {
    const location = existingLocationFromRow(row.location);
    if (location) locations.set(row.entry_id, location);
  }
  return locations;
}
