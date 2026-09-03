import { AuthGate } from "@/components/auth-gate";
import { GoalsWorkspace } from "@/components/goals-workspace";
import { WorkspaceShell } from "@/components/workspace-shell";
import { getGoalsWorkspace } from "@/lib/data/goal-records";
import { getSupabasePublicConfig } from "@/lib/supabase/config";

export const dynamic = "force-dynamic";

export default async function GoalsPage({
  searchParams,
}: {
  searchParams: Promise<{ entry?: string | string[] }>;
}) {
  if (!getSupabasePublicConfig()) return <AuthGate configured={false} />;

  const workspace = await getGoalsWorkspace();
  if (!workspace) return <AuthGate configured />;

  const requestedEntry = (await searchParams).entry;
  const initialGoalId =
    typeof requestedEntry === "string" ? requestedEntry : null;

  return (
    <WorkspaceShell
      activeDestination="goals"
      inboxCount={workspace.inboxCount}
      viewer={workspace.viewer}
    >
      <GoalsWorkspace
        collectionOptions={workspace.collectionOptions}
        goals={workspace.goals}
        initialGoalId={initialGoalId}
        linkOptions={workspace.linkOptions}
        loadError={workspace.loadError}
        ownerId={workspace.viewer.id}
        tagOptions={workspace.tagOptions}
      />
    </WorkspaceShell>
  );
}
