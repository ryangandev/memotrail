import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { cache } from "react";
import { ButtonLink } from "@/components/button";
import { PageHeader } from "@/components/page-header";
import { EntryDetailView } from "@/components/entry-detail-view";
import { PageFrame } from "@/components/page-frame";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import {
  entryTitle,
  validEntryID,
  type EntryDetail,
} from "@/lib/data/entry-detail";
import { loadEntryPhotos } from "@/lib/data/entry-photos";
import { chapterPage, loadChapterContents } from "@/lib/data/chapter-contents";
import styles from "@/components/entry-detail-view.module.css";

export const dynamic = "force-dynamic";

type ItemPageProps = {
  params: Promise<{ entry: string }>;
  searchParams: Promise<{ page?: string | string[] }>;
};

// The page and its metadata read the same item once per request.
const loadItem = cache(async (entry: string) => {
  const context = await getAuthenticatedContext();
  if (!context || !validEntryID(entry)) return null;
  const load = () => context.client.rpc("entry_detail", { p_entry_id: entry });
  let result = await load();
  if (result.error) {
    await new Promise((resolve) => setTimeout(resolve, 50));
    result = await load();
  }
  return {
    context,
    failed: Boolean(result.error),
    item: result.error ? null : (result.data as EntryDetail | null),
  };
});

export async function generateMetadata({
  params,
}: ItemPageProps): Promise<Metadata> {
  const item = (await loadItem((await params).entry))?.item;
  return item ? { title: `${entryTitle(item)} | MemoTrail` } : {};
}

export default async function WikiItemPage({
  params,
  searchParams,
}: ItemPageProps) {
  const { entry } = await params;
  const page = chapterPage((await searchParams).page);
  if (!validEntryID(entry)) {
    return (await getAuthenticatedContext()) ? <UnavailableItem /> : null;
  }

  const loaded = await loadItem(entry);
  if (!loaded) return null;
  const { context, failed, item } = loaded;
  const active = item && !item.deleted_at;
  // A Chapter lists the Entries dated inside it. One with no calendar date has no days to hold any.
  const isChapter = active && item.item_subtype === "chapter";
  // Photos of an item in Trash show from Trash, where it can be restored.
  const [photos, contents] = await Promise.all([
    active ? loadEntryPhotos(context.client, context.userId, item.id) : null,
    isChapter && item.occurred_start
      ? loadChapterContents(context.client, item.id, page)
      : null,
  ]);
  // A page past the last one opens the first, as Library does.
  if (item && contents && page > 1 && !contents.failed) {
    if (contents.entries.length === 0) redirect(`/items/${item.id}`);
  }

  return (
    <PageFrame className={styles.workspace} variant="compact">
      {failed ? (
        <p role="alert">This item could not load. Refresh to try again.</p>
      ) : item ? (
        <EntryDetailView
          chapter={
            isChapter
              ? { contents, now: new Date().toISOString(), page }
              : null
          }
          entry={item}
          ownerId={context.viewer.id}
          photos={photos}
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
      <ButtonLink href="/library" variant="secondary">
        Back to Library
      </ButtonLink>
    </section>
  );
}
