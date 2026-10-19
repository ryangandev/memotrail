import "server-only";

import {
  entryRowGroup,
  entryRowLabels,
  entryRowSnippet,
  type EntryRowSnippetPart,
} from "./entry-row";
import {
  chapterEntryCountLabel,
  loadChapterEntryCounts,
  loadEntryRowDetails,
  type EntryRowDetails,
} from "./entry-row-details";
import { getAuthenticatedContext } from "./inbox";
import { storedOccurrence, type Occurrence } from "./occurrence";
import { getSearchWorkspace, type SearchWorkspace } from "./search";
import { SEARCH_PAGE_SIZE, type ParsedSearchRequest } from "./search-input";
import { wikiEntryHref } from "./wiki-item";
import { getWikiItemsWorkspace, wikiItemsPageSize } from "./wiki-items";

/** Everything Library draws for one Entry. */
export type LibraryRow = {
  date: string | null;
  dateTime: string | null;
  /** The line under the title, with the words a search matched marked. */
  excerpt: EntryRowSnippetPart[];
  href: string;
  id: string;
  isChapter: boolean;
  isFirstTime: boolean;
  /** Why a search matched it; empty when Library is browsing or filtering. */
  matchReasons: string[];
  occurrence: Occurrence;
  tags: string[];
  thumbnail: EntryRowDetails["photo"];
  title: string;
};

/**
 * Browse lists every Entry by the date it happened; filter does the same for the Entries that
 * match the filters; search ranks Entries by how well they match the words.
 */
export type LibraryMode = "browse" | "filter" | "search";

export type LibraryView = {
  error: string | null;
  mode: LibraryMode;
  page: number;
  pageCount: number;
  rows: LibraryRow[];
  search: SearchWorkspace;
  totalCount: number;
};

/** One page of Library for the address it was opened at. */
export async function getLibraryView(
  parsed: ParsedSearchRequest,
  browsePage: number,
): Promise<LibraryView | null> {
  const { request } = parsed;
  const mode: LibraryMode = !request.hasCriteria
    ? "browse"
    : request.query
      ? "search"
      : "filter";
  const [search, browse, context] = await Promise.all([
    getSearchWorkspace(parsed),
    mode === "browse" ? getWikiItemsWorkspace(browsePage) : null,
    getAuthenticatedContext(),
  ]);
  if (!search || !context || (mode === "browse" && !browse)) return null;

  const now = new Date();
  // Under a month heading the year is already said.
  const year = mode === "search" ? "auto" : "hide";

  const base = browse
    ? browse.items.map((item) => {
        const occurrence = storedOccurrence(item);
        return {
          body: item.excerpt,
          id: item.id,
          isChapter: item.itemSubtype === "chapter",
          isFirstTime: item.isFirstTime,
          matchReasons: [] as string[],
          occurrence,
          tags: null as string[] | null,
          title: item.title,
        };
      })
    : search.entries.map((entry) => {
        const occurrence = storedOccurrence({
          datePrecision: entry.datePrecision,
          occurredEnd: entry.occurredEnd,
          occurredLabel: entry.occurredLabel,
          occurredStart: entry.occurredAt,
          occurredTimezone: entry.occurredTimezone,
        });
        return {
          body: entry.meaningPassage ?? entry.body,
          id: entry.id,
          isChapter: entry.itemSubtype === "chapter",
          isFirstTime: entry.isFirstTime,
          matchReasons: mode === "search" ? entry.matchReasons : [],
          occurrence,
          tags: entry.tagNames,
          title: entry.title ?? "",
        };
      });

  const [details, chapterCounts] = await Promise.all([
    loadEntryRowDetails(
      context.client,
      base.map((row) => row.id),
      { tags: mode === "browse" },
    ),
    loadChapterEntryCounts(
      context.client,
      base.filter((row) => row.isChapter).map((row) => row.id),
    ),
  ]);

  const rows = base.map((row): LibraryRow => {
    const labels = entryRowLabels({
      isChapter: row.isChapter,
      now,
      occurrence: row.occurrence,
      title: row.title,
      year,
    });
    // Under the Undated heading a row needs no date of its own.
    const undatedGroup =
      mode !== "search" && entryRowGroup(row.occurrence).key === "undated";
    const excerpt = entryRowSnippet(
      row.body,
      mode === "search" ? search.request.query : "",
    );
    const count = row.isChapter
      ? chapterEntryCountLabel(chapterCounts.get(row.id))
      : null;
    const detail = details.get(row.id);
    return {
      date: undatedGroup && !row.occurrence.occurredLabel ? null : labels.date,
      dateTime: labels.dateTime,
      excerpt: count
        ? [
            { match: false, text: excerpt.length ? `${count} · ` : count },
            ...excerpt,
          ]
        : excerpt,
      href: wikiEntryHref(row),
      id: row.id,
      isChapter: row.isChapter,
      isFirstTime: row.isFirstTime,
      matchReasons: row.matchReasons,
      occurrence: row.occurrence,
      tags: row.tags ?? detail?.tagNames ?? [],
      thumbnail: detail?.photo ?? null,
      title: labels.title,
    };
  });

  const totalCount = browse
    ? (browse.items[0]?.totalCount ?? 0)
    : search.totalCount;
  const pageSize = browse ? wikiItemsPageSize : SEARCH_PAGE_SIZE;
  return {
    error: browse ? browse.error : search.loadError,
    mode,
    page: browse ? browsePage : request.page,
    pageCount: Math.max(1, Math.ceil(totalCount / pageSize)),
    rows,
    search,
    totalCount,
  };
}
