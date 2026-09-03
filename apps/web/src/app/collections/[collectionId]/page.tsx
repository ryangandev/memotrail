import { notFound } from "next/navigation";
import { AuthGate } from "@/components/auth-gate";
import { CollectionsWorkspace } from "@/components/collections-workspace";
import { WorkspaceShell } from "@/components/workspace-shell";
import { getCollectionsWorkspace } from "@/lib/data/collections";
import {
  parseCollectionId,
  parseCollectionPage,
} from "@/lib/data/collections-input";
import { getSupabasePublicConfig } from "@/lib/supabase/config";

export const dynamic = "force-dynamic";

export default async function CollectionDetailPage({
  params,
  searchParams,
}: {
  params: Promise<{ collectionId: string }>;
  searchParams: Promise<{ page?: string | string[] }>;
}) {
  const isConfigured = Boolean(getSupabasePublicConfig());

  if (!isConfigured) {
    return <AuthGate configured={false} />;
  }

  const collectionId = parseCollectionId((await params).collectionId);
  const page = parseCollectionPage((await searchParams).page);

  if (!collectionId || !page) {
    notFound();
  }

  const workspace = await getCollectionsWorkspace({ collectionId, page });

  if (!workspace) {
    return <AuthGate configured />;
  }

  if (!workspace.loadError && !workspace.selectedCollection) {
    notFound();
  }

  if (
    !workspace.detailLoadError &&
    workspace.selectedCollection &&
    page > 1 &&
    workspace.entries.length === 0 &&
    workspace.selectedCollection.entryCount > 0
  ) {
    notFound();
  }

  return (
    <WorkspaceShell
      activeDestination="collections"
      inboxCount={workspace.inboxCount}
      viewer={workspace.viewer}
    >
      <CollectionsWorkspace workspace={workspace} />
    </WorkspaceShell>
  );
}
