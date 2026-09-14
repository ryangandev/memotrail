import { CollectionsWorkspace } from "@/components/collections-workspace";
import { getCollectionsWorkspace } from "@/lib/data/collections";

export const dynamic = "force-dynamic";

export default async function CollectionsPage() {
  const workspace = await getCollectionsWorkspace();

  if (!workspace) {
    return null;
  }

  return <CollectionsWorkspace workspace={workspace} />;
}
