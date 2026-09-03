import { AuthGate } from "@/components/auth-gate";
import { HabitsWorkspace } from "@/components/habits-workspace";
import { WorkspaceShell } from "@/components/workspace-shell";
import { getHabitsWorkspace } from "@/lib/data/habits";
import {
  parseHabitsRequest,
  type RawHabitsParams,
} from "@/lib/data/habits-request";
import { getSupabasePublicConfig } from "@/lib/supabase/config";

export const dynamic = "force-dynamic";

export default async function HabitsPage({
  searchParams,
}: {
  searchParams: Promise<RawHabitsParams>;
}) {
  const isConfigured = Boolean(getSupabasePublicConfig());

  if (!isConfigured) {
    return <AuthGate configured={false} />;
  }

  const fallbackDate = new Date().toISOString().slice(0, 10);
  const request = parseHabitsRequest(await searchParams, fallbackDate);
  const workspace = await getHabitsWorkspace({
    habitId: request.habitId,
    localDate: request.referenceDate,
    year: request.selectedYear,
  });

  if (!workspace) {
    return <AuthGate configured />;
  }

  return (
    <WorkspaceShell
      activeDestination="habits"
      inboxCount={workspace.inboxCount}
      viewer={workspace.viewer}
    >
      <HabitsWorkspace
        hasExplicitDate={request.hasExplicitDate}
        workspace={workspace}
      />
    </WorkspaceShell>
  );
}
