import { AIPausedSettings } from "@/components/ai-paused-settings";
import { getAuthenticatedContext } from "@/lib/data/inbox";

export const dynamic = "force-dynamic";

export default async function AISettingsPage() {
  const context = await getAuthenticatedContext();
  if (!context) return null;
  return <AIPausedSettings />;
}
