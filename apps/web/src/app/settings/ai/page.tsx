import { AISettings } from "@/components/ai-settings";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import { aiProviderConfigured } from "@/lib/ai/server";
import type { AIWorkspace } from "@/lib/ai/contracts";
export const dynamic = "force-dynamic";
export default async function AISettingsPage() {
  const context = await getAuthenticatedContext();
  if (!context) return null;
  const { data, error } = await context.client.rpc("ai_workspace");
  return error || !data ? (
    <p role="alert">Could not load AI settings. Refresh to try again.</p>
  ) : (
    <AISettings
      initial={data as AIWorkspace}
      configured={aiProviderConfigured()}
    />
  );
}
