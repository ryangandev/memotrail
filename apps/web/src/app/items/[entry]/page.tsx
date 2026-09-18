import Link from "next/link";
import { EntryHistoryView } from "@/components/entry-history-view";
import { PageFrame } from "@/components/page-frame";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import { validHistoryID, type EntryHistory } from "@/lib/data/history";
import styles from "@/app/history/page.module.css";

export const dynamic = "force-dynamic";

export default async function WikiItemPage({
  params,
}: {
  params: Promise<{ entry: string }>;
}) {
  const context = await getAuthenticatedContext();
  if (!context) return null;

  const { entry } = await params;
  if (!validHistoryID(entry)) {
    return <UnavailableItem />;
  }

  const loadItem = () =>
    context.client.rpc("entry_history", {
      p_entry_id: entry,
      p_limit: 20,
      p_offset: 0,
    });
  let result = await loadItem();
  if (result.error) {
    await new Promise((resolve) => setTimeout(resolve, 50));
    result = await loadItem();
  }

  return (
    <PageFrame className={styles.workspace} variant="compact">
      {result.error ? (
        <p role="alert">This item could not load. Refresh to try again.</p>
      ) : result.data ? (
        <EntryHistoryView
          history={result.data as EntryHistory}
          mode="detail"
          ownerId={context.viewer.id}
          page={1}
        />
      ) : (
        <UnavailableItem />
      )}
    </PageFrame>
  );
}

function UnavailableItem() {
  return (
    <section className={styles.detailUnavailable}>
      <p className={styles.eyebrow}>Life Wiki</p>
      <h1>Item unavailable</h1>
      <p>It may have moved to Trash or no longer be accessible.</p>
      <Link href="/library">Back to Library</Link>
    </section>
  );
}
