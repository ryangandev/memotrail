import { AuthGate } from "@/components/auth-gate";
import { WorkspaceShell } from "@/components/workspace-shell";
import { ExportSettings } from "@/components/export-settings";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import { getSupabasePublicConfig } from "@/lib/supabase/config";
export const dynamic = "force-dynamic";
export default async function ExportPage() {
  if (!getSupabasePublicConfig()) return <AuthGate configured={false} />;
  const context = await getAuthenticatedContext();
  if (!context) return <AuthGate configured />;
  const { data, error } = await context.client
    .from("export_snapshots")
    .select(
      "id,schema_version,captured_at,expires_at,row_count,json_bytes,datasets",
    )
    .gt("expires_at", new Date().toISOString())
    .order("captured_at", { ascending: false })
    .limit(2);
  return (
    <WorkspaceShell activeDestination="library" viewer={context.viewer}>
      <ExportSettings initial={data ?? []} initialError={Boolean(error)} />
    </WorkspaceShell>
  );
}
