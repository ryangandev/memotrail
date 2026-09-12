import { AuthGate } from "@/components/auth-gate";
import { WorkspaceShell } from "@/components/workspace-shell";
import { AISettings } from "@/components/ai-settings";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import { getSupabasePublicConfig } from "@/lib/supabase/config";
import { aiProviderConfigured } from "@/lib/ai/server";
import type { AIWorkspace } from "@/lib/ai/contracts";
export const dynamic = "force-dynamic";
export default async function AISettingsPage() {
  if (!getSupabasePublicConfig()) return <AuthGate configured={false} />;
  const context = await getAuthenticatedContext();
  if (!context) return <AuthGate configured />;
  const { data, error } = await context.client.rpc("ai_workspace");
  return (
    <WorkspaceShell activeDestination="library" viewer={context.viewer}>
      {error || !data ? (
        <p role="alert">Could not load AI settings. Refresh to try again.</p>
      ) : (
        <AISettings
          initial={data as AIWorkspace}
          configured={aiProviderConfigured()}
        />
      )}
    </WorkspaceShell>
  );
}
