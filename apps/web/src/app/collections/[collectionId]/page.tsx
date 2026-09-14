import { notFound } from "next/navigation";
import { CollectionsWorkspace } from "@/components/collections-workspace";
import { getCollectionsWorkspace } from "@/lib/data/collections";
import {
  parseCollectionId,
  parseCollectionPage,
} from "@/lib/data/collections-input";

export const dynamic = "force-dynamic";

export default async function CollectionDetailPage({
  params,
  searchParams,
}: {
  params: Promise<{ collectionId: string }>;
  searchParams: Promise<{ page?: string | string[] }>;
}) {
  const collectionId = parseCollectionId((await params).collectionId);
  const page = parseCollectionPage((await searchParams).page);

  if (!collectionId || !page) {
    notFound();
  }

  const workspace = await getCollectionsWorkspace({ collectionId, page });

  if (!workspace) {
    return null;
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

  return <CollectionsWorkspace workspace={workspace} />;
}
