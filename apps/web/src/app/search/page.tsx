import Link from "next/link";
import { AuthGate } from "@/components/auth-gate";
import { Icon } from "@/components/icon";
import { WorkspaceShell } from "@/components/workspace-shell";
import {
  SEARCH_PAGE_SIZE,
  parseSearchRequest,
  searchPageHref,
  type RawSearchParams,
  type SearchRequest,
} from "@/lib/data/search-input";
import { getSearchWorkspace, type SearchEntry } from "@/lib/data/search";
import { getSupabasePublicConfig } from "@/lib/supabase/config";
import styles from "./page.module.css";

export const dynamic = "force-dynamic";

const entryTypeOptions = [
  ["standard", "Standard Entry"],
  ["first_time", "First Time"],
  ["life_stage", "Life Stage"],
  ["home", "Home"],
  ["vehicle", "Vehicle"],
  ["goal", "Goal"],
] as const;

export default async function SearchPage({
  searchParams,
}: {
  searchParams: Promise<RawSearchParams>;
}) {
  const isConfigured = Boolean(getSupabasePublicConfig());

  if (!isConfigured) {
    return <AuthGate configured={false} />;
  }

  const parsed = parseSearchRequest(await searchParams);
  const workspace = await getSearchWorkspace(parsed);

  if (!workspace) {
    return <AuthGate configured />;
  }

  const {
    collectionOptions,
    entries,
    filtersError,
    inboxCount,
    loadError,
    request,
    tagOptions,
    totalCount,
    viewer,
  } = workspace;

  return (
    <WorkspaceShell
      activeDestination="search"
      inboxCount={inboxCount}
      viewer={viewer}
    >
      <div className={styles.content}>
        <header className={styles.pageHeader}>
          <div>
            <p className={styles.eyebrow}>Your personal archive</p>
            <h1>Search your trail</h1>
            <p>
              Find an Entry by what you wrote, when it happened, or how you
              organized it.
            </p>
          </div>
          <Link className={styles.newEntryButton} href="/inbox#capture-title">
            <Icon name="plus" />
            <span>New entry</span>
          </Link>
        </header>

        <section className={styles.searchSurface} aria-label="Entry search">
          <form action="/search" method="get">
            <div className={styles.queryRow}>
              <label className={styles.queryField} htmlFor="trail-search">
                <Icon name="search" size={21} />
                <span className={styles.visuallyHidden}>
                  Search your Entries
                </span>
                <input
                  autoFocus
                  defaultValue={request.query}
                  id="trail-search"
                  maxLength={200}
                  name="q"
                  placeholder="A phrase, place, date, Collection, or tag..."
                  type="search"
                />
              </label>
              <button className={styles.searchSubmit} type="submit">
                Search
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
                <span>Type</span>
                <select defaultValue={request.entryTypes[0] ?? ""} name="type">
                  <option value="">All Types</option>
                  {entryTypeOptions.map(([value, label]) => (
                    <option key={value} value={value}>
                      {label}
                    </option>
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

            {filtersError ? (
              <p className={styles.filterNotice} role="status">
                {filtersError}
              </p>
            ) : null}
          </form>
        </section>

        <SearchResults
          entries={entries}
          loadError={loadError}
          request={request}
          totalCount={totalCount}
        />
      </div>
    </WorkspaceShell>
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
            A word from the note, a year, a Collection, or even part of a
            Chinese phrase can bring the Entry back.
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
          <strong>No matching Entries</strong>
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
          <span>{entryTypeLabel(entry.entryType)}</span>
          {entry.inboxStatus === "unreviewed" ? <span>In Inbox</span> : null}
          <time dateTime={entry.occurredAt ?? entry.updatedAt}>
            {resultDateLabel(entry)}
          </time>
        </div>
        <h3>
          <Link
            className={styles.sourceLink}
            href={`/history?entry=${entry.id}`}
          >
            {entry.title ?? firstUsefulLine(body) ?? "Untitled Entry"}
          </Link>
        </h3>
      </header>

      {body ? <p className={styles.resultBody}>{body}</p> : null}

      {hasLongBody ? (
        <details className={styles.fullEntry}>
          <summary>Read full note</summary>
          <p>{body}</p>
        </details>
      ) : null}

      {entry.collectionNames.length || entry.tagNames.length ? (
        <div className={styles.organization} aria-label="Entry organization">
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
  return `${count} ${count === 1 ? "Entry" : "Entries"}`;
}

function entryTypeLabel(value: string) {
  const known = entryTypeOptions.find(([entryType]) => entryType === value);

  if (known) {
    return known[1];
  }

  return value
    .split("_")
    .filter(Boolean)
    .map((part) => `${part.charAt(0).toLocaleUpperCase()}${part.slice(1)}`)
    .join(" ");
}

function resultDateLabel(entry: SearchEntry) {
  if (entry.occurredLabel) {
    return entry.occurredLabel;
  }

  if (!entry.occurredAt) {
    return "Date not set";
  }

  const date = new Date(entry.occurredAt);
  const options: Intl.DateTimeFormatOptions = {
    day: "numeric",
    month: "short",
    year: "numeric",
  };

  try {
    return new Intl.DateTimeFormat("en-US", {
      ...options,
      timeZone: entry.occurredTimezone ?? "UTC",
    }).format(date);
  } catch {
    return new Intl.DateTimeFormat("en-US", {
      ...options,
      timeZone: "UTC",
    }).format(date);
  }
}

function firstUsefulLine(value: string) {
  return value
    .split(/\r?\n/)
    .map((line) => line.trim())
    .find(Boolean);
}
