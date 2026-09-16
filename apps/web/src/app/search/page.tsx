import {
  occurrenceLabel,
  occurrenceSpanLabel,
  validTimezone,
} from "@/lib/data/occurrence";
import Link from "next/link";
import { EntryRichTextContent } from "@/components/entry-rich-text-content";
import { Icon } from "@/components/icon";
import { AISearchForm } from "@/components/ai-search-form";
import { PageFrame } from "@/components/page-frame";
import {
  SEARCH_PAGE_SIZE,
  parseSearchRequest,
  searchPageHref,
  type RawSearchParams,
  type SearchRequest,
} from "@/lib/data/search-input";
import { getSearchWorkspace, type SearchEntry } from "@/lib/data/search";
import {
  wikiEntryHref,
  wikiItemIdentityLabel,
  wikiItemSearchGroups,
} from "@/lib/data/wiki-item";
import styles from "./page.module.css";

export const dynamic = "force-dynamic";

export default async function SearchPage({
  searchParams,
}: {
  searchParams: Promise<RawSearchParams>;
}) {
  const parameters = await searchParams;
  const parsed = parseSearchRequest(parameters);
  const workspace = await getSearchWorkspace(parsed);

  if (!workspace) {
    return null;
  }

  const {
    collectionOptions,
    entries,
    filtersError,
    loadError,
    request,
    tagOptions,
    totalCount,
  } = workspace;

  return (
    <PageFrame variant="standard">
      <header className={styles.pageHeader}>
        <div>
          <p className={styles.eyebrow}>Your personal archive</p>
          <h1>Search your trail</h1>
          <p>Find anything in your Life Wiki by what you remember.</p>
        </div>
        <Link className={styles.newEntryButton} href="/inbox#capture-title">
          <Icon name="plus" />
          <span>New entry</span>
        </Link>
      </header>

      <AISearchForm
        key={JSON.stringify(request)}
        keywordResults={
          <>
            <SearchResults
              entries={entries}
              loadError={loadError}
              request={request}
              totalCount={totalCount}
            />
          </>
        }
      >
        <section className={styles.searchSurface} aria-label="Entry search">
          <div className={styles.queryRow}>
            <label className={styles.queryField} htmlFor="trail-search">
              <Icon name="search" size={21} />
              <span className={styles.visuallyHidden}>
                Search your Life Wiki
              </span>
              <input
                autoFocus
                defaultValue={request.query}
                id="trail-search"
                maxLength={200}
                name="q"
                placeholder="A phrase, date, or question about your life..."
                type="search"
              />
            </label>
            <button className={styles.searchSubmit} type="submit">
              Search
            </button>
            <button
              className={styles.askSubmit}
              name="mode"
              value="ai"
              type="submit"
            >
              Ask AI
            </button>
          </div>

          <div className={styles.searchScope}>
            <span>Keyword search</span>
            <p>
              Titles, notes, local dates, Collections, tags, and structured
              details
            </p>
          </div>

          <fieldset className={styles.filters}>
            <legend>Refine results</legend>

            <label>
              <span>Kind or type</span>
              <select
                defaultValue={request.itemClassifications[0] ?? ""}
                name="type"
              >
                <option value="">All Kinds and types</option>
                {wikiItemSearchGroups.map((group) => (
                  <optgroup key={group.label} label={group.label}>
                    {group.options.map((option) => (
                      <option key={option.value} value={option.value}>
                        {option.label}
                      </option>
                    ))}
                  </optgroup>
                ))}
              </select>
            </label>

            <label>
              <span>Collection</span>
              <select
                defaultValue={request.collectionNames[0] ?? ""}
                disabled={collectionOptions.length === 0}
                name="collection"
              >
                <option value="">All Collections</option>
                {collectionOptions.map((name) => (
                  <option key={name.toLocaleLowerCase()} value={name}>
                    {name}
                  </option>
                ))}
              </select>
            </label>

            <label>
              <span>Tag</span>
              <select
                defaultValue={request.tagNames[0] ?? ""}
                disabled={tagOptions.length === 0}
                name="tag"
              >
                <option value="">All tags</option>
                {tagOptions.map((name) => (
                  <option key={name.toLocaleLowerCase()} value={name}>
                    {name}
                  </option>
                ))}
              </select>
            </label>

            <label>
              <span>From</span>
              <input
                defaultValue={request.dateFrom ?? ""}
                name="from"
                type="date"
              />
            </label>

            <label>
              <span>To</span>
              <input
                defaultValue={request.dateTo ?? ""}
                name="to"
                type="date"
              />
            </label>

            {request.hasCriteria ? (
              <Link className={styles.clearFilters} href="/search">
                Clear all
              </Link>
            ) : (
              <span className={styles.clearPlaceholder} aria-hidden="true" />
            )}
          </fieldset>

          <p className={styles.dateGuidance}>
            Date filters include overlapping recorded periods in each
            item&apos;s time zone. Partial dates may overlap; unanchored dates
            remain searchable without date filters.
          </p>
          {filtersError ? (
            <p className={styles.filterNotice} role="status">
              {filtersError}
            </p>
          ) : null}
        </section>
      </AISearchForm>
    </PageFrame>
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

  if (!request.hasCriteria) {
    return (
      <div className={styles.message}>
        <Icon name="sparkle" size={23} />
        <div>
          <strong>Start with anything you remember</strong>
          <p>
            A word from the writing, a year, a Collection, or even part of a
            Chinese phrase can bring an item back.
          </p>
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
      <header className={styles.resultsHeader}>
        <div>
          <h2 id="results-heading">Results</h2>
          <span aria-live="polite">{resultCountLabel(totalCount)}</span>
        </div>
        {totalCount > SEARCH_PAGE_SIZE ? (
          <span>
            Page {request.page} · {SEARCH_PAGE_SIZE} at a time
          </span>
        ) : null}
      </header>

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

  return (
    <article className={styles.resultCard}>
      <header>
        <div className={styles.resultMeta}>
          <span>
            {wikiItemIdentityLabel(entry.itemKind, entry.itemSubtype)}
          </span>
          {entry.inboxStatus === "unreviewed" ? <span>In Inbox</span> : null}
          <time dateTime={entry.occurredAt ?? undefined}>
            {resultDateLabel(entry)}
          </time>
        </div>
        <h3>
          <Link className={styles.sourceLink} href={wikiEntryHref(entry)}>
            {entry.title ?? firstUsefulLine(body) ?? "Untitled Entry"}
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

      {entry.collectionNames.length || entry.tagNames.length ? (
        <div className={styles.organization} aria-label="Item organization">
          {entry.collectionNames.map((name) => (
            <span key={`collection:${name.toLocaleLowerCase()}`}>{name}</span>
          ))}
          {entry.tagNames.map((name) => (
            <span key={`tag:${name.toLocaleLowerCase()}`}>#{name}</span>
          ))}
        </div>
      ) : null}

      <footer>
        <span>Matched in</span>
        <div>
          {entry.matchReasons.map((reason) => (
            <span key={reason}>{reason}</span>
          ))}
        </div>
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
        <Link href={searchPageHref(request, request.page - 1)}>Previous</Link>
      ) : (
        <span />
      )}
      <span>Page {request.page}</span>
      {hasNext ? (
        <Link href={searchPageHref(request, request.page + 1)}>Next</Link>
      ) : (
        <span />
      )}
    </nav>
  );
}

function resultCountLabel(count: number) {
  return `${count} ${count === 1 ? "item" : "items"}`;
}

function resultDateLabel(entry: SearchEntry) {
  const occurrence = {
    ...entry,
    occurredTimezone: validTimezone(entry.occurredTimezone)
      ? entry.occurredTimezone
      : "UTC",
  };
  return entry.occurredEnd !== null ||
    (entry.itemKind === "entity" &&
      ["home", "vehicle"].includes(entry.itemSubtype)) ||
    entry.itemSubtype === "life_stage"
    ? occurrenceSpanLabel(occurrence)
    : occurrenceLabel(occurrence);
}

function firstUsefulLine(value: string) {
  return value
    .split(/\r?\n/)
    .map((line) => line.trim())
    .find(Boolean);
}
