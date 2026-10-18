import { Button } from "@/components/button";
import { Badge } from "@/components/badge";
import {
  entryDisplayTitle,
  occurrenceLabel,
  occurrenceSpanLabel,
  validTimezone,
  type Occurrence,
} from "@/lib/data/occurrence";
import Link from "next/link";
import type { ReactNode } from "react";
import { EntryRichTextContent } from "@/components/entry-rich-text-content";
import { Icon } from "@/components/icon";
import { DatePickerField } from "@/components/date-picker-field";
import { SearchField } from "@/components/search-field";
import { SectionHeader } from "@/components/section-header";
import { SelectField } from "@/components/select-field";
import { SeparatedList } from "@/components/separated-list";
import {
  SEARCH_PAGE_SIZE,
  librarySearchHref,
  type SearchRequest,
} from "@/lib/data/search-input";
import { type SearchEntry, type SearchWorkspace } from "@/lib/data/search";
import {
  wikiEntryHref,
  wikiItemIdentityLabel,
  wikiItemSearchGroups,
} from "@/lib/data/wiki-item";
import styles from "./library-search.module.css";

export function LibrarySearch({
  browse,
  workspace,
}: {
  browse: ReactNode;
  workspace: SearchWorkspace;
}) {
  const { entries, filtersError, loadError, request, tagOptions, totalCount } =
    workspace;
  const advancedFilterCount = [
    request.itemClassifications.length > 0,
    request.tagNames.length > 0,
    Boolean(request.dateFrom),
    Boolean(request.dateTo),
  ].filter(Boolean).length;

  return (
    <>
      <form action="/library" method="get">
        <section className={styles.searchSurface} aria-label="Entry search">
          <div className={styles.queryRow}>
            <SearchField
              defaultValue={request.query}
              hideLabel
              id="trail-search"
              label="Search your Life Wiki"
              maxLength={200}
              name="q"
              placeholder="A phrase, date, or question about your life..."
              size="large"
            />
            <Button variant="primary" type="submit">
              Search
            </Button>
          </div>

          <div className={styles.searchScope}>
            <Badge size="medium">Keyword search</Badge>
            <p>Titles, notes, local dates, tags, and structured details</p>
            {request.hasCriteria ? (
              <Link className={styles.clearSearch} href="/library">
                Clear all
              </Link>
            ) : null}
          </div>

          <details
            className={styles.advancedFilters}
            open={advancedFilterCount > 0}
          >
            <summary>
              Filters
              {advancedFilterCount > 0
                ? ` · ${advancedFilterCount} active`
                : ""}
            </summary>
            <fieldset className={styles.filters}>
              <legend>Refine results</legend>

              <SelectField
                defaultValue={request.itemClassifications[0] ?? ""}
                label="Record"
                name="type"
                size="small"
              >
                <option value="">All records</option>
                {wikiItemSearchGroups.map((group) => (
                  <optgroup key={group.label} label={group.label}>
                    {group.options.map((option) => (
                      <option key={option.value} value={option.value}>
                        {option.label}
                      </option>
                    ))}
                  </optgroup>
                ))}
              </SelectField>

              <SelectField
                defaultValue={request.tagNames[0] ?? ""}
                disabled={tagOptions.length === 0}
                label="Tag"
                name="tag"
                size="small"
              >
                <option value="">All tags</option>
                {tagOptions.map((name) => (
                  <option key={name.toLocaleLowerCase()} value={name}>
                    {name}
                  </option>
                ))}
              </SelectField>

              <DatePickerField
                defaultValue={request.dateFrom ?? ""}
                key={`from-${request.dateFrom ?? ""}`}
                label="From"
                name="from"
                size="small"
              />
              <DatePickerField
                defaultValue={request.dateTo ?? ""}
                key={`to-${request.dateTo ?? ""}`}
                label="To"
                name="to"
                size="small"
              />
            </fieldset>
          </details>

          {filtersError ? (
            <p className={styles.filterNotice} role="status">
              {filtersError}
            </p>
          ) : null}
        </section>
      </form>
      {request.hasCriteria || loadError ? (
        <SearchResults
          entries={entries}
          loadError={loadError}
          request={request}
          totalCount={totalCount}
        />
      ) : (
        browse
      )}
    </>
  );
}

function SearchResults({
  entries,
  loadError,
  request,
  totalCount,
}: {
  entries: SearchEntry[];
  loadError: string | null;
  request: SearchRequest;
  totalCount: number;
}) {
  if (loadError) {
    return (
      <div className={styles.message} role="alert">
        <Icon name="search" size={23} />
        <div>
          <strong>Search unavailable</strong>
          <p>{loadError}</p>
        </div>
      </div>
    );
  }

  if (entries.length === 0) {
    return (
      <div className={styles.message}>
        <Icon name="search" size={23} />
        <div>
          <strong>No matching items</strong>
          <p>Try fewer words, remove a filter, or search for a broader date.</p>
        </div>
      </div>
    );
  }

  return (
    <section
      className={styles.resultsSection}
      aria-labelledby="results-heading"
    >
      <SectionHeader
        action={
          totalCount > SEARCH_PAGE_SIZE ? (
            <span className={styles.resultsPage}>
              Page {request.page} · {SEARCH_PAGE_SIZE} at a time
            </span>
          ) : null
        }
        className={styles.resultsHeader}
        detail={<span aria-live="polite">{resultCountLabel(totalCount)}</span>}
        headingId="results-heading"
        title="Results"
        variant="list"
      />

      <div className={styles.resultList}>
        {entries.map((entry) => (
          <SearchResultCard entry={entry} key={entry.id} />
        ))}
      </div>

      <SearchPagination request={request} totalCount={totalCount} />
    </section>
  );
}

function SearchResultCard({ entry }: { entry: SearchEntry }) {
  const body = entry.body.trim();
  const hasLongBody = body.length > 280;
  const occurrence = resultOccurrence(entry);

  return (
    <article className={styles.resultCard}>
      <header>
        <div className={styles.resultMeta}>
          <Badge tone="neutral">
            {wikiItemIdentityLabel(
              entry.itemKind,
              entry.itemSubtype,
              entry.milestoneShape
                ? {
                    isFirstTime: entry.isFirstTime,
                    shape: entry.milestoneShape,
                  }
                : null,
            )}
          </Badge>
          {/* An untitled Entry is already named by its date. */}
          {entry.title ? (
            <time dateTime={entry.occurredAt ?? undefined}>
              {resultDateLabel(entry, occurrence)}
            </time>
          ) : null}
        </div>
        <h3>
          <Link className={styles.sourceLink} href={wikiEntryHref(entry)}>
            {entryDisplayTitle(entry.title, occurrence)}
          </Link>
        </h3>
      </header>

      {body ? (
        <EntryRichTextContent
          body={body}
          className={styles.resultBody}
          richText={entry.bodyRich}
        />
      ) : null}

      {hasLongBody ? (
        <details className={styles.fullEntry}>
          <summary>Read full note</summary>
          <EntryRichTextContent
            body={body}
            className={styles.fullEntryBody}
            richText={entry.bodyRich}
          />
        </details>
      ) : null}

      {entry.tagNames.length ? (
        <div className={styles.organization} aria-label="Item organization">
          {entry.tagNames.map((name) => (
            <Badge key={`tag:${name.toLocaleLowerCase()}`} tone="neutral">
              #{name}
            </Badge>
          ))}
        </div>
      ) : null}

      <footer>
        <span className={styles.matchLabel}>Matched in</span>
        <SeparatedList className={styles.matchReasons}>
          {entry.matchReasons.map((reason) => (
            <span key={reason}>{reason}</span>
          ))}
        </SeparatedList>
      </footer>
    </article>
  );
}

function SearchPagination({
  request,
  totalCount,
}: {
  request: SearchRequest;
  totalCount: number;
}) {
  const hasPrevious = request.page > 1;
  const hasNext = request.offset + SEARCH_PAGE_SIZE < totalCount;

  if (!hasPrevious && !hasNext) {
    return null;
  }

  return (
    <nav className={styles.pagination} aria-label="Search result pages">
      {hasPrevious ? (
        <Link href={librarySearchHref(request, request.page - 1)}>
          Previous
        </Link>
      ) : (
        <span />
      )}
      <span>Page {request.page}</span>
      {hasNext ? (
        <Link href={librarySearchHref(request, request.page + 1)}>Next</Link>
      ) : (
        <span />
      )}
    </nav>
  );
}

function resultCountLabel(count: number) {
  return `${count} ${count === 1 ? "item" : "items"}`;
}

function resultOccurrence(entry: SearchEntry): Occurrence {
  return {
    ...entry,
    occurredTimezone: validTimezone(entry.occurredTimezone)
      ? entry.occurredTimezone
      : "UTC",
  };
}

function resultDateLabel(entry: SearchEntry, occurrence: Occurrence) {
  return (entry.itemKind === "entity" &&
    ["home", "vehicle"].includes(entry.itemSubtype)) ||
    entry.milestoneShape === "period"
    ? occurrenceSpanLabel(occurrence)
    : occurrenceLabel(occurrence);
}
