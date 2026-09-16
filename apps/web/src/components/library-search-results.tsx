import Link from "next/link";
import {
  hasLibrarySearchScope,
  hasUnappliedLibraryFilters,
  libraryKindsForSearch,
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
  if (!hasLibrarySearchScope(request) && hasUnappliedLibraryFilters(request))
    return (
      <p className={styles.dateGuidance}>
        People and Places do not use the selected Collection, tag, date, or
        non-Entity classification.
      </p>
    );
  if (!hasLibrarySearchScope(request)) return null;
  const libraryKinds = libraryKindsForSearch(request);
  const sectionLabel =
    libraryKinds.length === 1
      ? libraryKinds[0] === "person"
        ? "People"
        : "Places"
      : "People and Places";
  return (
    <section className={styles.resultsSection} aria-label={sectionLabel}>
      <header className={styles.resultsHeader}>
        <div>
          <h2>{sectionLabel}</h2>
          <span>
            {result ? `${result.total_count} matches` : "Keyword search"}
          </span>
        </div>
      </header>
      <p className={styles.dateGuidance}>
        Names, notes, and location details. No AI required. Trash is excluded.
      </p>
      {error ? (
        <p role="alert">{error}</p>
      ) : (
        <>
          {result?.items.length === 0 && <p>No matching {sectionLabel}.</p>}
          <div className={styles.resultList}>
            {result?.items.map((item) => (
              <article
                className={styles.resultCard}
                key={`${item.kind}:${item.id}`}
              >
                <div className={styles.resultMeta}>
                  <span>{item.kind === "person" ? "Person" : "Place"}</span>
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
