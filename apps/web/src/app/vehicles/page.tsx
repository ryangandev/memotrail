import { VehiclesWorkspace } from "@/components/vehicles-workspace";
import { getVehiclesWorkspace } from "@/lib/data/vehicle-records";
import { redirect } from "next/navigation";

export const dynamic = "force-dynamic";

export default async function VehiclesPage({
  searchParams,
}: {
  searchParams: Promise<{ entry?: string | string[] }>;
}) {
  const requestedEntry = (await searchParams).entry;
  if (typeof requestedEntry === "string")
    redirect(`/vehicles/${requestedEntry}`);
  const workspace = await getVehiclesWorkspace();
  if (!workspace) return null;

  return (
    <VehiclesWorkspace
      loadError={workspace.loadError}
      ownerId={workspace.viewer.id}
      defaultTimezone={workspace.defaultTimezone}
      tagOptions={workspace.tagOptions}
      vehicles={workspace.vehicles}
    />
  );
}
