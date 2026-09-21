import { LocationMapWorkspace } from "@/components/location-map-workspace";
import { getLocationMapWorkspace } from "@/lib/data/location-map";

export const dynamic = "force-dynamic";

export default async function MapPage() {
  const workspace = await getLocationMapWorkspace();
  if (!workspace) return null;
  return (
    <LocationMapWorkspace
      {...workspace}
      mapConfigured={Boolean(process.env.GEOAPIFY_API_KEY?.trim())}
    />
  );
}
