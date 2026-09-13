import Link from "next/link";
import {
  hasLibrarySearchScope,
  libraryItemHref,
  librarySearchHref,
  librarySearchPageSize,
  type LibrarySearchResult,
} from "@/lib/data/library-search";
import type { SearchRequest } from "@/lib/data/search-input";
import styles from "@/app/search/page.module.css";

export function LibrarySearchResults({
  request,
  result,
  error,
  page,
}: {
  request: SearchRequest;
  result: LibrarySearchResult | null;
  error: string | null;
  page: number;
}) {
  if (!request.query) return null;
  if (!hasLibrarySearchScope(request))
    return (
      <p className={styles.dateGuidance}>
        Clear Entry filters to also search People, Places and Habits.
      </p>
    );
  return (
    <section
      className={styles.resultsSection}
      aria-label="People, Places and Habits"
    >
      <header className={styles.resultsHeader}>
        <div>
          <h2>People, Places and Habits</h2>
          <span>
            {result ? `${result.total_count} matches` : "Keyword search"}
          </span>
        </div>
      </header>
      <p className={styles.dateGuidance}>
        Names, notes, location details and Habit check-in notes. No AI required.
        Trash and archived Habits are excluded.
      </p>
      {error ? (
        <p role="alert">{error}</p>
      ) : (
        <>
          {result?.items.length === 0 && (
            <p>No matching People, Places or Habits.</p>
          )}
          <div className={styles.resultList}>
            {result?.items.map((item) => (
              <article
                className={styles.resultCard}
                key={`${item.kind}:${item.id}`}
              >
                <div className={styles.resultMeta}>
                  <span>
                    {item.kind === "person"
                      ? "Person"
                      : item.kind === "place"
                        ? "Place"
                        : "Habit"}
                  </span>
                </div>
                <h3>
                  <Link
                    className={styles.sourceLink}
                    href={libraryItemHref(item)}
                  >
                    {item.name}
                  </Link>
                </h3>
                {item.excerpt && (
                  <p className={styles.resultBody}>{item.excerpt}</p>
                )}
                <p className={styles.dateGuidance}>
                  Matched:{" "}
                  {item.match_reasons.length
                    ? item.match_reasons.join(", ")
                    : "Names, notes and details"}
                </p>
              </article>
            ))}
          </div>
          <nav
            className={`${styles.pagination} ${styles.libraryPagination}`}
            aria-label="Library search pages"
          >
            {page > 1 && (
              <Link href={librarySearchHref(request, page - 1)}>
                Previous library matches
              </Link>
            )}
            {result &&
              page * librarySearchPageSize < result.total_count &&
              page < 501 && (
                <Link href={librarySearchHref(request, page + 1)}>
                  Next library matches
                </Link>
              )}
            {page === 501 &&
              result &&
              page * librarySearchPageSize < result.total_count && (
                <p>Refine your search to reach more matches.</p>
              )}
          </nav>
        </>
      )}
    </section>
  );
}
