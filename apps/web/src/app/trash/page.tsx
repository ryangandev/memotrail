import { notFound } from "next/navigation";
import { AuthGate } from "@/components/auth-gate";
import { TrashWorkspace } from "@/components/trash-workspace";
import { WorkspaceShell } from "@/components/workspace-shell";
import { getTrashWorkspace } from "@/lib/data/trash";
import { parseTrashPage, TRASH_PAGE_SIZE } from "@/lib/data/trash-input";
import { getSupabasePublicConfig } from "@/lib/supabase/config";

export const dynamic = "force-dynamic";

export default async function TrashPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const isConfigured = Boolean(getSupabasePublicConfig());

  if (!isConfigured) {
    return <AuthGate configured={false} />;
  }

  const page = parseTrashPage((await searchParams).page);

  if (!page) {
    notFound();
  }

  const workspace = await getTrashWorkspace(page);

  if (!workspace) {
    return <AuthGate configured />;
  }

  if (
    page > 1 &&
    !workspace.loadError &&
    workspace.items.length === 0 &&
    workspace.totalCount <= (page - 1) * TRASH_PAGE_SIZE
  ) {
    notFound();
  }

  return (
    <WorkspaceShell
      activeDestination="trash"
      inboxCount={workspace.inboxCount}
      viewer={workspace.viewer}
    >
      <TrashWorkspace workspace={workspace} />
    </WorkspaceShell>
  );
}
