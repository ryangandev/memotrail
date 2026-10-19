import { Button, ButtonLink } from "@/components/button";
import { EmptyState } from "@/components/empty-state";
import { EntryRow, EntryRowGroup, EntryRowList } from "@/components/entry-row";
import { Icon } from "@/components/icon";
import { LibraryFilters } from "@/components/library-filters";
import { groupEntryRows } from "@/lib/data/entry-row";
import type { LibraryRow, LibraryView } from "@/lib/data/library";
import { librarySearchHref } from "@/lib/data/search-input";
import styles from "./library-search.module.css";

/**
 * Library below its header: search and filters, then every Entry grouped by the month it
 * happened, or search results ranked by how well they match.
 */
export function LibrarySearch({ view }: { view: LibraryView }) {
  const { mode, search } = view;
  const { filtersError, request, semantic, tagOptions } = search;
  // Meaning is part of search whenever it is on, even if the service is down right now.
  const searchesByMeaning =
    semantic.state === "on" || semantic.state === "unavailable";
  const emptyLibrary =
    mode === "browse" && !view.error && view.totalCount === 0;

  if (emptyLibrary) {
    return (
      <div className={styles.emptyLibrary}>
        <EmptyState
          actions={
            <ButtonLink href="/settings/import" variant="secondary">
              Import Entries
            </ButtonLink>
          }
          description="Every Entry you write or import appears here, newest first by the date it happened."
          title="Nothing in Library yet"
        />
      </div>
    );
  }

  return (
    <>
      <LibraryFilters request={request} tagOptions={tagOptions}>
        {filtersError ? (
          <p className={styles.filterNotice} role="status">
            {filtersError}
          </p>
        ) : null}
        {request.query && semantic.state === "unavailable" ? (
          <p className={styles.filterNotice} role="status">
            Search by meaning is unavailable right now, so these results match
            your words only.
          </p>
        ) : null}
        {request.query && searchesByMeaning && semantic.pendingCount > 0 ? (
          <p className={styles.statusNotice} role="status">
            Still preparing {semantic.pendingCount}{" "}
            {semantic.pendingCount === 1 ? "Entry" : "Entries"} for search by
            meaning.
          </p>
        ) : null}
      </LibraryFilters>

      <LibraryResults searchesByMeaning={searchesByMeaning} view={view} />
    </>
  );
}

function LibraryResults({
  searchesByMeaning,
  view,
}: {
  searchesByMeaning: boolean;
  view: LibraryView;
}) {
  const { error, mode, rows } = view;

  if (error) {
    return (
      <div className={styles.results} role="alert">
        <EmptyState
          description={error}
          icon={<Icon name="search" size={20} />}
          title={
            mode === "browse" ? "Library could not load" : "Search unavailable"
          }
        />
      </div>
    );
  }

  if (rows.length === 0) {
    return (
      <div className={styles.results}>
        <EmptyState
          actions={
            <ButtonLink href="/library" scroll={false} variant="secondary">
              Clear all
            </ButtonLink>
          }
          description={
            mode === "search"
              ? searchesByMeaning
                ? "Try fewer words, describe it differently, or remove a filter."
                : "Try fewer words, another spelling, or remove a filter."
              : "Try another filter or a wider range of dates."
          }
          icon={<Icon name="search" size={20} />}
          title="No Entries match"
        />
      </div>
    );
  }

  return (
    <section aria-label="Entries" className={styles.results}>
      {mode === "search" ? (
        <EntryRowList label="Search results">
          {rows.map((row) => (
            <LibraryEntryRow key={row.id} row={row} />
          ))}
        </EntryRowList>
      ) : (
        groupEntryRows(rows, (row) => row.occurrence).map((group) => (
          <EntryRowGroup key={group.key} label={group.label}>
            {group.items.map((row) => (
              <LibraryEntryRow key={row.id} row={row} />
            ))}
          </EntryRowGroup>
        ))
      )}
      <LibraryPagination view={view} />
    </section>
  );
}

function LibraryEntryRow({ row }: { row: LibraryRow }) {
  return (
    <EntryRow
      date={row.date}
      dateTime={row.dateTime}
      excerpt={
        row.excerpt.length
          ? row.excerpt.map((part, index) =>
              part.match ? <mark key={index}>{part.text}</mark> : part.text,
            )
          : null
      }
      href={row.href}
      isChapter={row.isChapter}
      isFirstTime={row.isFirstTime}
      matchReasons={row.matchReasons}
      tags={row.tags}
      thumbnail={row.thumbnail}
      title={row.title}
    />
  );
}

function LibraryPagination({ view }: { view: LibraryView }) {
  const { page, pageCount } = view;
  if (pageCount <= 1) return null;
  const href = (target: number) =>
    view.mode === "browse"
      ? target > 1
        ? `/library?page=${target}`
        : "/library"
      : librarySearchHref(view.search.request, target);

  return (
    <nav aria-label="Library pages" className={styles.pagination}>
      {page > 1 ? (
        <ButtonLink href={href(page - 1)} variant="quiet">
          Previous
        </ButtonLink>
      ) : (
        <Button disabled variant="quiet">
          Previous
        </Button>
      )}
      <span>
        Page {page} of {pageCount}
      </span>
      {page < pageCount ? (
        <ButtonLink href={href(page + 1)} variant="secondary">
          Next
        </ButtonLink>
      ) : (
        <Button disabled variant="secondary">
          Next
        </Button>
      )}
    </nav>
  );
}
