import { AISettings } from "@/components/ai-settings";
import { PageFrame } from "@/components/page-frame";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import { aiProviderConfigured } from "@/lib/ai/server";
import type { AIWorkspace } from "@/lib/ai/contracts";
export const dynamic = "force-dynamic";
export default async function AISettingsPage() {
  const context = await getAuthenticatedContext();
  if (!context) return null;
  const monthStart = new Date();
  monthStart.setUTCDate(1);
  monthStart.setUTCHours(0, 0, 0, 0);
  const [workspace, requestCount] = await Promise.all([
    context.client.rpc("ai_workspace"),
    context.client
      .from("ai_usage")
      .select("id", { count: "exact", head: true })
      .gte("created_at", monthStart.toISOString())
      .neq("feature", "connection"),
  ]);
  const { data, error } = workspace;
  return error || !data ? (
    <PageFrame variant="compact">
      <p role="alert">Could not load AI settings. Refresh to try again.</p>
    </PageFrame>
  ) : (
    <AISettings
      initial={data as AIWorkspace}
      configured={aiProviderConfigured()}
      monthRequestCount={requestCount.error ? null : requestCount.count}
    />
  );
}
