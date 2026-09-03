import { AuthGate } from "@/components/auth-gate";
import { VehiclesWorkspace } from "@/components/vehicles-workspace";
import { WorkspaceShell } from "@/components/workspace-shell";
import { getVehiclesWorkspace } from "@/lib/data/vehicle-records";
import { getSupabasePublicConfig } from "@/lib/supabase/config";

export const dynamic = "force-dynamic";

export default async function VehiclesPage({
  searchParams,
}: {
  searchParams: Promise<{ entry?: string | string[] }>;
}) {
  if (!getSupabasePublicConfig()) return <AuthGate configured={false} />;

  const workspace = await getVehiclesWorkspace();
  if (!workspace) return <AuthGate configured />;

  const requestedEntry = (await searchParams).entry;
  const initialVehicleId =
    typeof requestedEntry === "string" ? requestedEntry : null;

  return (
    <WorkspaceShell
      activeDestination="vehicles"
      inboxCount={workspace.inboxCount}
      viewer={workspace.viewer}
    >
      <VehiclesWorkspace
        collectionOptions={workspace.collectionOptions}
        initialVehicleId={initialVehicleId}
        loadError={workspace.loadError}
        ownerId={workspace.viewer.id}
        tagOptions={workspace.tagOptions}
        vehicles={workspace.vehicles}
      />
    </WorkspaceShell>
  );
}
