import { VehiclesWorkspace } from "@/components/vehicles-workspace";
import { getCaptureExtractionSource } from "@/lib/data/capture-extraction";
import { getVehiclesWorkspace } from "@/lib/data/vehicle-records";

export const dynamic = "force-dynamic";

export default async function VehiclesPage({
  searchParams,
}: {
  searchParams: Promise<{
    entry?: string | string[];
    source?: string | string[];
  }>;
}) {
  const params = await searchParams;
  const requestedEntry = params.entry;
  const requestedSource = params.source;
  const [workspace, sourceCapture] = await Promise.all([
    getVehiclesWorkspace(),
    getCaptureExtractionSource(
      typeof requestedSource === "string" ? requestedSource : null,
    ),
  ]);
  if (!workspace) return null;

  const initialVehicleId =
    typeof requestedEntry === "string" ? requestedEntry : null;

  return (
    <VehiclesWorkspace
      collectionOptions={workspace.collectionOptions}
      initialVehicleId={initialVehicleId}
      loadError={workspace.loadError}
      ownerId={workspace.viewer.id}
      sourceCapture={sourceCapture}
      tagOptions={workspace.tagOptions}
      vehicles={workspace.vehicles}
    />
  );
}
