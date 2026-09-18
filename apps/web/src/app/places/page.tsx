import { PlacesWorkspace } from "@/components/places-workspace";
import { getPlacesWorkspace } from "@/lib/data/place-records";

export const dynamic = "force-dynamic";

export default async function PlacesPage({
  searchParams,
}: {
  searchParams: Promise<{ place?: string | string[] }>;
}) {
  const workspace = await getPlacesWorkspace();
  if (!workspace) return null;

  const requestedPlace = (await searchParams).place;
  const initialPlaceId =
    typeof requestedPlace === "string" ? requestedPlace : null;

  return (
    <PlacesWorkspace
      initialPlaceId={initialPlaceId}
      loadError={workspace.loadError}
      places={workspace.places}
    />
  );
}
