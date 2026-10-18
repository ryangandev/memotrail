import { PageHeader } from "@/components/page-header";
import { Badge } from "@/components/badge";
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
import { wikiItemKindLabel, wikiItemSubtypeLabel } from "@/lib/data/wiki-item";
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
        <ul aria-label="Library items" className={styles.wikiList}>
          {workspace.items.map((item) => {
            const occurrence = storedOccurrence(item);
            // An untitled Entry is already named by its date.
            const date = item.title.trim()
              ? wikiItemDateLabel(item, occurrence)
              : null;
            return (
              <li key={item.id}>
                <Link href={wikiItemHref(item)}>
                  <div className={styles.wikiBadges}>
                    <Badge size="micro" uppercase>
                      {wikiItemKindLabel(item.itemKind)}
                    </Badge>
                    {wikiItemSubtypeLabel(item.itemKind, item.itemSubtype) !==
                    wikiItemKindLabel(item.itemKind) ? (
                      <Badge size="micro" tone="neutral" uppercase>
                        {wikiItemSubtypeLabel(item.itemKind, item.itemSubtype)}
                      </Badge>
                    ) : null}
                  </div>
                  {date ? <small>{date}</small> : null}
                  <strong>{entryDisplayTitle(item.title, occurrence)}</strong>
                  {item.excerpt ? <p>{item.excerpt}</p> : null}
                </Link>
              </li>
            );
          })}
        </ul>
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

// Homes and Vehicles span the time they were part of the user's life.
function wikiItemDateLabel(item: WikiItemSummary, occurrence: Occurrence) {
  if (!item.occurredStart && !item.occurredLabel) return null;
  return item.itemKind === "entity" &&
    ["home", "vehicle"].includes(item.itemSubtype)
    ? occurrenceSpanLabel(occurrence)
    : occurrenceLabel(occurrence);
}
