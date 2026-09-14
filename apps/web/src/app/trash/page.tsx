import { notFound } from "next/navigation";
import { TrashWorkspace } from "@/components/trash-workspace";
import { getTrashWorkspace } from "@/lib/data/trash";
import { parseTrashPage, TRASH_PAGE_SIZE } from "@/lib/data/trash-input";

export const dynamic = "force-dynamic";

export default async function TrashPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const page = parseTrashPage((await searchParams).page);

  if (!page) {
    notFound();
  }

  const workspace = await getTrashWorkspace(page);

  if (!workspace) {
    return null;
  }

  if (
    page > 1 &&
    !workspace.loadError &&
    workspace.items.length === 0 &&
    workspace.totalCount <= (page - 1) * TRASH_PAGE_SIZE
  ) {
    notFound();
  }

  return <TrashWorkspace workspace={workspace} />;
}
