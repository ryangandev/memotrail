import { PageHeader } from "@/components/page-header";
import { Badge } from "@/components/badge";
import Link from "next/link";
import { redirect } from "next/navigation";
import { Icon } from "@/components/icon";
import { LibrarySearch } from "@/components/library-search";
import { PageFrame } from "@/components/page-frame";
import { getSearchWorkspace } from "@/lib/data/search";
import {
  parseSearchRequest,
  type RawSearchParams,
} from "@/lib/data/search-input";
import { wikiItemKindLabel, wikiItemSubtypeLabel } from "@/lib/data/wiki-item";
import {
  getWikiItemsWorkspace,
  wikiItemHref,
  wikiItemsPage,
  wikiItemsPageSize,
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
  const needsOrganizing =
    firstParameter(parameters.show) === needsOrganizingView;
  const [searchWorkspace, browseWorkspace] = await Promise.all([
    getSearchWorkspace(parsed),
    parsed.request.hasCriteria
      ? Promise.resolve(null)
      : getWikiItemsWorkspace({
          itemKind: null,
          needsOrganizing,
          page,
          query: "",
        }),
  ]);
  if (!searchWorkspace || (!parsed.request.hasCriteria && !browseWorkspace))
    return null;
  if (
    browseWorkspace &&
    !browseWorkspace.error &&
    page > 1 &&
    browseWorkspace.items.length === 0
  ) {
    redirect(libraryPageHref(1, needsOrganizing));
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
            <LibraryBrowse
              needsOrganizing={needsOrganizing}
              page={page}
              workspace={browseWorkspace}
            />
          ) : null
        }
        workspace={searchWorkspace}
      />

      <footer className={styles.libraryFooter}>
        <Link href="/history">
          <Icon name="clock" size={16} />
          <span>Version history</span>
          <Icon name="chevron" size={14} />
        </Link>
      </footer>
    </PageFrame>
  );
}

function LibraryBrowse({
  needsOrganizing,
  page,
  workspace,
}: {
  needsOrganizing: boolean;
  page: number;
  workspace: NonNullable<Awaited<ReturnType<typeof getWikiItemsWorkspace>>>;
}) {
  const totalCount = workspace.items[0]?.totalCount ?? 0;
  const pageCount = Math.max(1, Math.ceil(totalCount / wikiItemsPageSize));

  return (
    <section aria-labelledby="library-items-heading">
      <div className={styles.sectionHeading}>
        <h2 id="library-items-heading">
          {needsOrganizing ? "Needs organizing" : "All items"}
        </h2>
        <div className={styles.sectionMeta}>
          <span>
            {totalCount} {totalCount === 1 ? "item" : "items"}
          </span>
          {needsOrganizing ? (
            <Link href={libraryPageHref(1, false)}>Show all items</Link>
          ) : workspace.needsOrganizingCount > 0 ? (
            <Link href={libraryPageHref(1, true)}>
              {workspace.needsOrganizingCount} need organizing
            </Link>
          ) : null}
        </div>
      </div>
      {needsOrganizing ? (
        <p className={styles.sectionNote}>
          Entries without a title or a tag. Give one either and it leaves this
          list.
        </p>
      ) : null}
      {workspace.error ? (
        <p role="alert">{workspace.error}</p>
      ) : workspace.items.length === 0 ? (
        <div className={styles.wikiEmpty}>
          {needsOrganizing ? (
            <>
              <strong>Everything has a place</strong>
              <p>New captures without a title or tag will show up here.</p>
            </>
          ) : (
            <>
              <strong>No matching items</strong>
              <p>Try another phrase or category, or capture something new.</p>
            </>
          )}
        </div>
      ) : (
        <ul aria-label="Library items" className={styles.wikiList}>
          {workspace.items.map((item) => (
            <li key={`${item.recordSource}:${item.id}`}>
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
                <small>{wikiItemDateLabel(item)}</small>
                <strong>{item.title}</strong>
                {excerptAfterTitle(item) ? (
                  <p>{excerptAfterTitle(item)}</p>
                ) : null}
              </Link>
            </li>
          ))}
        </ul>
      )}

      {pageCount > 1 ? (
        <nav className={styles.pagination} aria-label="Life Wiki pages">
          {page > 1 ? (
            <Link href={libraryPageHref(page - 1, needsOrganizing)}>
              Previous
            </Link>
          ) : (
            <span />
          )}
          <span>
            Page {page} of {pageCount}
          </span>
          {page < pageCount ? (
            <Link href={libraryPageHref(page + 1, needsOrganizing)}>Next</Link>
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

const needsOrganizingView = "needs-organizing";

function libraryPageHref(page: number, needsOrganizing: boolean) {
  const parameters = new URLSearchParams();
  if (needsOrganizing) parameters.set("show", needsOrganizingView);
  if (page > 1) parameters.set("page", String(page));
  const query = parameters.toString();
  return query ? `/library?${query}` : "/library";
}

// An Entry without a title is listed by the start of its writing, so the
// excerpt continues after that start instead of repeating it.
function excerptAfterTitle(item: { excerpt: string; title: string }) {
  return item.excerpt.startsWith(item.title)
    ? item.excerpt.slice(item.title.length).trim()
    : item.excerpt;
}

function wikiItemDateLabel(item: {
  occurredEnd: string | null;
  occurredStart: string | null;
  updatedAt: string;
}) {
  const format = (value: string) =>
    new Intl.DateTimeFormat("en", {
      dateStyle: "medium",
      timeZone: "UTC",
    }).format(new Date(value));
  if (item.occurredStart) {
    return item.occurredEnd
      ? `${format(item.occurredStart)} to ${format(item.occurredEnd)}`
      : format(item.occurredStart);
  }
  return `Updated ${format(item.updatedAt)}`;
}
