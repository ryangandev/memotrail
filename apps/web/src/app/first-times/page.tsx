import { AuthGate } from "@/components/auth-gate";
import { FirstTimesWorkspace } from "@/components/first-times-workspace";
import { WorkspaceShell } from "@/components/workspace-shell";
import { getFirstTimesWorkspace } from "@/lib/data/first-times";
import { getSupabasePublicConfig } from "@/lib/supabase/config";

export const dynamic = "force-dynamic";

export default async function FirstTimesPage() {
  const isConfigured = Boolean(getSupabasePublicConfig());

  if (!isConfigured) {
    return <AuthGate configured={false} />;
  }

  const workspace = await getFirstTimesWorkspace();

  if (!workspace) {
    return <AuthGate configured />;
  }

  return (
    <WorkspaceShell
      activeDestination="first-times"
      inboxCount={workspace.inboxCount}
      viewer={workspace.viewer}
    >
      <FirstTimesWorkspace
        collectionOptions={workspace.collectionOptions}
        entries={workspace.entries}
        loadError={workspace.loadError}
        ownerId={workspace.viewer.id}
        tagOptions={workspace.tagOptions}
      />
    </WorkspaceShell>
  );
}
