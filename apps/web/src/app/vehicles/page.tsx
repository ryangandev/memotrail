import { VehiclesWorkspace } from "@/components/vehicles-workspace";
import { getVehiclesWorkspace } from "@/lib/data/vehicle-records";

export const dynamic = "force-dynamic";

export default async function VehiclesPage({
  searchParams,
}: {
  searchParams: Promise<{ entry?: string | string[] }>;
}) {
  const workspace = await getVehiclesWorkspace();
  if (!workspace) return null;

  const requestedEntry = (await searchParams).entry;
  const initialVehicleId =
    typeof requestedEntry === "string" ? requestedEntry : null;

  return (
    <VehiclesWorkspace
      collectionOptions={workspace.collectionOptions}
      initialVehicleId={initialVehicleId}
      loadError={workspace.loadError}
      ownerId={workspace.viewer.id}
      tagOptions={workspace.tagOptions}
      vehicles={workspace.vehicles}
    />
  );
}
