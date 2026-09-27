import { HomeDashboard } from "@/components/home-dashboard";
import { getHomeWorkspace } from "@/lib/data/home";

export const dynamic = "force-dynamic";

export default async function HomePage() {
  const workspace = await getHomeWorkspace();
  if (!workspace) return null;
  return <HomeDashboard workspace={workspace} />;
}
