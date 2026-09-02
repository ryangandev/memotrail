import { AuthGate } from "@/components/auth-gate";
import { TimelineWorkspace } from "@/components/timeline-workspace";
import { WorkspaceShell } from "@/components/workspace-shell";
import { getTimelineWorkspace } from "@/lib/data/timeline";
import { getSupabasePublicConfig } from "@/lib/supabase/config";

export const dynamic = "force-dynamic";

export default async function TimelinePage() {
  const isConfigured = Boolean(getSupabasePublicConfig());

  if (!isConfigured) {
    return <AuthGate configured={false} />;
  }

  const workspace = await getTimelineWorkspace();

  if (!workspace) {
    return <AuthGate configured />;
  }

  return (
    <WorkspaceShell
      activeDestination="timeline"
      inboxCount={workspace.inboxCount}
      viewer={workspace.viewer}
    >
      <TimelineWorkspace
        loadError={workspace.loadError}
        referenceDate={new Date().toISOString()}
        tracks={workspace.tracks}
      />
    </WorkspaceShell>
  );
}
