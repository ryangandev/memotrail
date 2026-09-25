import { PageHeader } from "@/components/page-header";
import { ButtonLink, Button } from "@/components/button";
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
import { DatePickerField } from "@/components/date-picker-field";
import { SearchField } from "@/components/search-field";
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
      <PageHeader
        title={<>Search your trail</>}
        eyebrow={<>Your personal archive</>}
        description={<>Find anything in your Life Wiki by what you remember.</>}
        actions={
          <>
            <ButtonLink href="/inbox#capture-title">
              <Icon name="plus" />
              <span>New entry</span>
            </ButtonLink>
          </>
        }
      />

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
            <SearchField
              autoFocus
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
            <Button variant="primary" name="mode" value="ai" type="submit">
              Ask AI
            </Button>
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
              <span>Record</span>
              <select
                defaultValue={request.itemClassifications[0] ?? ""}
                name="type"
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

            {request.hasCriteria ? (
              <Link className={styles.clearFilters} href="/search">
                Clear all
              </Link>
            ) : (
              <span className={styles.clearPlaceholder} aria-hidden="true" />
            )}
          </fieldset>

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
  return (entry.itemKind === "entity" &&
    ["home", "vehicle"].includes(entry.itemSubtype)) ||
    entry.itemSubtype === "period"
    ? occurrenceSpanLabel(occurrence)
    : occurrenceLabel(occurrence);
}

function firstUsefulLine(value: string) {
  return value
    .split(/\r?\n/)
    .map((line) => line.trim())
    .find(Boolean);
}
