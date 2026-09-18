import { PageHeader } from "@/components/page-header";
import Link from "next/link";
import { ExplorationView } from "@/components/exploration-view";
import { PageFrame } from "@/components/page-frame";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import { explorationID } from "@/lib/ai/exploration";
import { explorationWorkspace } from "@/lib/ai/exploration-server";
import styles from "./page.module.css";
export const dynamic = "force-dynamic";
export default async function ExplorePage({
  searchParams,
}: {
  searchParams: Promise<{ entry?: string }>;
}) {
  const context = await getAuthenticatedContext();
  if (!context) return null;
  const { entry } = await searchParams;
  let workspace = null;
  if (explorationID(entry)) {
    try {
      workspace = await explorationWorkspace(context.client, entry);
    } catch {
      await new Promise((resolve) => setTimeout(resolve, 50));
      try {
        workspace = await explorationWorkspace(context.client, entry);
      } catch {
        /* Render recoverable unavailable state after one bounded retry. */
      }
    }
  }
  return (
    <PageFrame className={styles.workspace} variant="compact">
      <PageHeader
        title={<>Explore with AI</>}
        eyebrow={<>ROOM FOR A THOUGHT TO GROW</>}
        description={
          <>A separate conversation. Your original words stay yours.</>
        }
      />
      {workspace ? (
        <ExplorationView
          key={`${context.viewer.id}:${entry}`}
          initial={workspace}
        />
      ) : (
        <p role="alert">
          This Entry could not be loaded or is in Trash.{" "}
          <Link href="/inbox">Back to Inbox</Link>
        </p>
      )}
    </PageFrame>
  );
}
