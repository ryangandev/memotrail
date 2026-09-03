import { AuthGate } from "@/components/auth-gate";
import { CollectionsWorkspace } from "@/components/collections-workspace";
import { WorkspaceShell } from "@/components/workspace-shell";
import { getCollectionsWorkspace } from "@/lib/data/collections";
import { getSupabasePublicConfig } from "@/lib/supabase/config";

export const dynamic = "force-dynamic";

export default async function CollectionsPage() {
  const isConfigured = Boolean(getSupabasePublicConfig());

  if (!isConfigured) {
    return <AuthGate configured={false} />;
  }

  const workspace = await getCollectionsWorkspace();

  if (!workspace) {
    return <AuthGate configured />;
  }

  return (
    <WorkspaceShell
      activeDestination="collections"
      inboxCount={workspace.inboxCount}
      viewer={workspace.viewer}
    >
      <CollectionsWorkspace workspace={workspace} />
    </WorkspaceShell>
  );
}
