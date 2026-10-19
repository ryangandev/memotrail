import { PageHeader } from "@/components/page-header";
import { EntryList } from "@/components/entry-list";
import Link from "next/link";
import { redirect } from "next/navigation";
import { LibrarySearch } from "@/components/library-search";
import { PageFrame } from "@/components/page-frame";
import { SectionHeader } from "@/components/section-header";
import { getSearchWorkspace } from "@/lib/data/search";
import {
  parseSearchRequest,
  type RawSearchParams,
} from "@/lib/data/search-input";
import {
  entryDisplayTitle,
  occurrenceLabel,
  occurrenceSpanLabel,
  storedOccurrence,
  type Occurrence,
} from "@/lib/data/occurrence";
import {
  getWikiItemsWorkspace,
  wikiItemHref,
  wikiItemsPage,
  wikiItemsPageSize,
  type WikiItemSummary,
} from "@/lib/data/wiki-items";
import styles from "./page.module.css";

export const dynamic = "force-dynamic";

export default async function LibraryPage({
  searchParams,
}: {
  searchParams: Promise<RawSearchParams>;
}) {
  const parameters = await searchParams;
  const parsed = parseSearchRequest({
    ...parameters,
    type: parameters.type ?? parameters.kind,
  });
  const page = wikiItemsPage(firstParameter(parameters.page));
  const [searchWorkspace, browseWorkspace] = await Promise.all([
    getSearchWorkspace(parsed),
    parsed.request.hasCriteria
      ? Promise.resolve(null)
      : getWikiItemsWorkspace(page),
  ]);
  if (!searchWorkspace || (!parsed.request.hasCriteria && !browseWorkspace))
    return null;
  if (
    browseWorkspace &&
    !browseWorkspace.error &&
    page > 1 &&
    browseWorkspace.items.length === 0
  ) {
    redirect(libraryPageHref(1));
  }

  return (
    <PageFrame className={styles.content} variant="standard">
      <PageHeader
        title={<>Library</>}
        eyebrow={<>Your Life Wiki</>}
        description={
          <>
            Browse everything you have saved, or search across your Life Wiki.
          </>
        }
      />

      <LibrarySearch
        browse={
          browseWorkspace ? (
            <LibraryBrowse page={page} workspace={browseWorkspace} />
          ) : null
        }
        workspace={searchWorkspace}
      />
    </PageFrame>
  );
}

function LibraryBrowse({
  page,
  workspace,
}: {
  page: number;
  workspace: NonNullable<Awaited<ReturnType<typeof getWikiItemsWorkspace>>>;
}) {
  const totalCount = workspace.items[0]?.totalCount ?? 0;
  const pageCount = Math.max(1, Math.ceil(totalCount / wikiItemsPageSize));

  return (
    <section aria-labelledby="library-items-heading">
      <SectionHeader
        className={styles.sectionHeading}
        detail={`${totalCount} ${totalCount === 1 ? "item" : "items"}`}
        detailAlign="end"
        headingId="library-items-heading"
        title="All items"
        variant="list"
      />
      {workspace.error ? (
        <p role="alert">{workspace.error}</p>
      ) : workspace.items.length === 0 ? (
        <div className={styles.wikiEmpty}>
          <strong>No matching items</strong>
          <p>Try another phrase or category, or capture something new.</p>
        </div>
      ) : (
        <EntryList
          items={workspace.items.map((item) => {
            const occurrence = storedOccurrence(item);
            return {
              // An untitled Entry is already named by its date.
              date: item.title.trim()
                ? wikiItemDateLabel(item, occurrence)
                : null,
              excerpt: item.excerpt,
              href: wikiItemHref(item),
              id: item.id,
              isChapter: item.itemSubtype === "chapter",
              isFirstTime: item.isFirstTime,
              title: entryDisplayTitle(item.title, occurrence),
            };
          })}
          label="Library items"
        />
      )}

      {pageCount > 1 ? (
        <nav className={styles.pagination} aria-label="Life Wiki pages">
          {page > 1 ? (
            <Link href={libraryPageHref(page - 1)}>Previous</Link>
          ) : (
            <span />
          )}
          <span>
            Page {page} of {pageCount}
          </span>
          {page < pageCount ? (
            <Link href={libraryPageHref(page + 1)}>Next</Link>
          ) : (
            <span />
          )}
        </nav>
      ) : null}
    </section>
  );
}

function firstParameter(value: string | string[] | undefined) {
  return Array.isArray(value) ? (value[0] ?? "") : (value ?? "");
}

function libraryPageHref(page: number) {
  return page > 1 ? `/library?page=${page}` : "/library";
}

// A Chapter spans the time it covered.
function wikiItemDateLabel(item: WikiItemSummary, occurrence: Occurrence) {
  if (!item.occurredStart && !item.occurredLabel) return null;
  return item.itemSubtype === "chapter"
    ? occurrenceSpanLabel(occurrence)
    : occurrenceLabel(occurrence);
}
