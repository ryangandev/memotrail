import { ButtonLink } from "@/components/button";
import { PageHeader } from "@/components/page-header";
import { EntryDetailView } from "@/components/entry-detail-view";
import { PageFrame } from "@/components/page-frame";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import { validEntryID, type EntryDetail } from "@/lib/data/entry-detail";
import styles from "@/components/entry-detail-view.module.css";

export const dynamic = "force-dynamic";

export default async function WikiItemPage({
  params,
}: {
  params: Promise<{ entry: string }>;
}) {
  const context = await getAuthenticatedContext();
  if (!context) return null;

  const { entry } = await params;
  if (!validEntryID(entry)) {
    return <UnavailableItem />;
  }

  const loadItem = () =>
    context.client.rpc("entry_detail", { p_entry_id: entry });
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
        <EntryDetailView
          entry={result.data as EntryDetail}
          ownerId={context.viewer.id}
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
      <PageHeader
        eyebrow="Life Wiki"
        title="Item unavailable"
        description="It may have moved to Trash or no longer be accessible."
      />
      <ButtonLink href="/library">Back to Library</ButtonLink>
    </section>
  );
}
