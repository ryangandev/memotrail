import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { cache } from "react";
import { ButtonLink } from "@/components/button";
import { EntryDetailView } from "@/components/entry-detail-view";
import { PageFrame } from "@/components/page-frame";
import { RouteFallback } from "@/components/route-fallback";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import {
  entryTitle,
  validEntryID,
  type EntryDetail,
} from "@/lib/data/entry-detail";
import { loadEntryChapters } from "@/lib/data/entry-chapters";
import { loadEntryPhotos } from "@/lib/data/entry-photos";
import { storedOccurrence } from "@/lib/data/occurrence";
import { chapterPage, loadChapterContents } from "@/lib/data/chapter-contents";
import {
  loadChapterReview,
  loadReviewSettings,
  reviewToday,
} from "@/lib/data/reviews";
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
  const pageParameter = (await searchParams).page;
  const page = chapterPage(pageParameter);
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
  const [photos, contents, chapters] = await Promise.all([
    active ? loadEntryPhotos(context.client, context.userId, item.id) : null,
    isChapter && item.occurred_start
      ? loadChapterContents(context.client, item.id, page)
      : null,
    // An Entry names the Chapters it falls inside.
    active && !isChapter
      ? loadEntryChapters(
          context.client,
          context.userId,
          storedOccurrence({
            datePrecision: item.date_precision,
            occurredEnd: item.occurred_end,
            occurredLabel: item.occurred_label,
            occurredStart: item.occurred_start,
            occurredTimezone: item.occurred_timezone,
          }),
        )
      : null,
  ]);
  const review = isChapter ? await loadReview(context.client, item.id) : null;
  // A page past the last one opens the first, as Library does.
  if (item && contents && page > 1 && !contents.failed) {
    if (contents.entries.length === 0) redirect(`/items/${item.id}`);
  }

  if (!failed && !item) return <UnavailableItem />;

  return (
    // A Chapter's lists use the wider frame; its writing keeps the reading measure inside it.
    <PageFrame width={isChapter ? "list" : "reading"}>
      {failed || !item ? (
        <p className={styles.alert} role="alert">
          This Entry could not load. Refresh to try again.
        </p>
      ) : (
        <EntryDetailView
          chapter={
            isChapter
              ? {
                  contents,
                  now: new Date().toISOString(),
                  page,
                  review,
                  // A page number in the address lists every Entry, page by page.
                  showAll: pageParameter !== undefined,
                }
              : null
          }
          chapters={chapters}
          entry={item}
          ownerId={context.viewer.id}
          photos={photos}
        />
      )}
    </PageFrame>
  );
}

/** A Chapter's review, shown only when its data and the review settings could be read. */
async function loadReview(
  client: NonNullable<
    Awaited<ReturnType<typeof getAuthenticatedContext>>
  >["client"],
  chapterId: string,
) {
  const { localDate, timezone } = await reviewToday();
  const [data, preferences] = await Promise.all([
    loadChapterReview(client, chapterId, localDate),
    loadReviewSettings(client),
  ]);
  return data && preferences
    ? { data, preferences, timezone, today: localDate }
    : null;
}

/** An Entry that is gone or was never there: the same page as any missing address. */
function UnavailableItem() {
  return (
    <RouteFallback
      actions={
        <>
          <ButtonLink href="/library">Open Library</ButtonLink>
          <ButtonLink href="/trash" variant="secondary">
            Open Trash
          </ButtonLink>
        </>
      }
      description="It may have moved to Trash, or it no longer exists."
      title="Entry unavailable"
    />
  );
}
