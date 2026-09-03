import { AuthGate } from "@/components/auth-gate";
import { PlacesWorkspace } from "@/components/places-workspace";
import { WorkspaceShell } from "@/components/workspace-shell";
import { getPlacesWorkspace } from "@/lib/data/place-records";
import { getSupabasePublicConfig } from "@/lib/supabase/config";

export const dynamic = "force-dynamic";

export default async function PlacesPage({
  searchParams,
}: {
  searchParams: Promise<{ place?: string | string[] }>;
}) {
  if (!getSupabasePublicConfig()) return <AuthGate configured={false} />;

  const workspace = await getPlacesWorkspace();
  if (!workspace) return <AuthGate configured />;

  const requestedPlace = (await searchParams).place;
  const initialPlaceId =
    typeof requestedPlace === "string" ? requestedPlace : null;

  return (
    <WorkspaceShell
      activeDestination="places"
      inboxCount={workspace.inboxCount}
      viewer={workspace.viewer}
    >
      <PlacesWorkspace
        initialPlaceId={initialPlaceId}
        linkOptions={workspace.linkOptions}
        loadError={workspace.loadError}
        places={workspace.places}
      />
    </WorkspaceShell>
  );
}
