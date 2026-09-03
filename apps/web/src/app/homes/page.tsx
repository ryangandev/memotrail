import { AuthGate } from "@/components/auth-gate";
import { HomesWorkspace } from "@/components/homes-workspace";
import { WorkspaceShell } from "@/components/workspace-shell";
import { getHomesWorkspace } from "@/lib/data/home-records";
import { getSupabasePublicConfig } from "@/lib/supabase/config";

export const dynamic = "force-dynamic";

export default async function HomesPage({
  searchParams,
}: {
  searchParams: Promise<{ entry?: string | string[] }>;
}) {
  if (!getSupabasePublicConfig()) {
    return <AuthGate configured={false} />;
  }

  const workspace = await getHomesWorkspace();

  if (!workspace) {
    return <AuthGate configured />;
  }

  const requestedEntry = (await searchParams).entry;
  const initialHomeId =
    typeof requestedEntry === "string" ? requestedEntry : null;

  return (
    <WorkspaceShell
      activeDestination="homes"
      inboxCount={workspace.inboxCount}
      viewer={workspace.viewer}
    >
      <HomesWorkspace
        collectionOptions={workspace.collectionOptions}
        homes={workspace.homes}
        initialHomeId={initialHomeId}
        loadError={workspace.loadError}
        ownerId={workspace.viewer.id}
        placeOptions={workspace.placeOptions}
        tagOptions={workspace.tagOptions}
      />
    </WorkspaceShell>
  );
}
