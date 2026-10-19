"use client";

import { useRouter } from "next/navigation";
import {
  useEffect,
  useId,
  useRef,
  useState,
  useTransition,
  type FormEvent,
  type ReactNode,
} from "react";
import { Button, ButtonLink, IconButton } from "@/components/button";
import { DatePickerField } from "@/components/date-picker-field";
import { Icon } from "@/components/icon";
import { SearchField } from "@/components/search-field";
import { SegmentedControl } from "@/components/segmented-control";
import {
  isISODate,
  librarySearchHref,
  SEARCH_QUERY_LIMIT,
  type SearchRequest,
} from "@/lib/data/search-input";
import styles from "./library-search.module.css";

type Show = "" | "entry" | "chapter" | "first_time" | "mixed";

const showOptions: readonly { label: string; value: Show }[] = [
  { label: "All", value: "" },
  { label: "Entries", value: "entry" },
  { label: "Chapters", value: "chapter" },
  { label: "First Times", value: "first_time" },
];

/** How long typing pauses before Library searches. */
const searchDelay = 400;

/**
 * Library's search and filters: a search field that searches as the person types, the
 * All, Entries, Chapters, and First Times control, and quiet Tags and Dates panels. Every change
 * updates the address, so a filtered Library can be bookmarked and the back button undoes it.
 * Without JavaScript the search field still submits as a form.
 */
export function LibraryFilters({
  children,
  request,
  tagOptions,
}: {
  /** Notices about this search, such as search by meaning being unavailable. */
  children?: ReactNode;
  request: SearchRequest;
  tagOptions: readonly string[];
}) {
  const router = useRouter();
  const [, startTransition] = useTransition();
  const panelId = useId();
  const [panel, setPanel] = useState<"tags" | "dates" | null>(() =>
    request.dateFrom || request.dateTo ? "dates" : null,
  );

  // The field keeps what the person is typing; a new address, such as Clear or Back, resets it.
  const [query, setQuery] = useState(request.query);
  const [shownQuery, setShownQuery] = useState(request.query);
  if (shownQuery !== request.query) {
    setShownQuery(request.query);
    setQuery(request.query);
  }

  const field = useRef<HTMLInputElement>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  useEffect(
    () => () => {
      if (timer.current) clearTimeout(timer.current);
    },
    [],
  );

  function go(next: Partial<SearchRequest>, mode: "push" | "replace" = "push") {
    if (timer.current) clearTimeout(timer.current);
    const href = librarySearchHref({ ...request, query, ...next }, 1);
    startTransition(() => {
      if (mode === "replace") router.replace(href, { scroll: false });
      else router.push(href, { scroll: false });
    });
  }

  function onQueryChange(value: string) {
    setQuery(value);
    if (timer.current) clearTimeout(timer.current);
    timer.current = setTimeout(() => {
      if (value.trim() !== request.query) {
        go({ query: value.trim() }, "replace");
      }
    }, searchDelay);
  }

  function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    go({ query: query.trim() });
  }

  const show: Show =
    request.itemClassifications.length === 0
      ? ""
      : request.itemClassifications.length === 1 &&
          showOptions.some(
            (option) => option.value === request.itemClassifications[0],
          )
        ? (request.itemClassifications[0] as Show)
        : "mixed";
  const selectedTags = new Set(
    request.tagNames.map((name) => name.toLocaleLowerCase()),
  );
  const datesActive = Boolean(request.dateFrom || request.dateTo);

  function toggleTag(name: string) {
    const key = name.toLocaleLowerCase();
    go({
      tagNames: selectedTags.has(key)
        ? request.tagNames.filter((tag) => tag.toLocaleLowerCase() !== key)
        : [...request.tagNames, name],
    });
  }

  return (
    <div
      aria-label="Library search"
      className={styles.searchSurface}
      role="search"
    >
      <form
        action="/library"
        className={styles.searchForm}
        method="get"
        onSubmit={onSubmit}
      >
        <SearchField
          className={styles.searchField}
          hideLabel
          label="Search Library"
          maxLength={SEARCH_QUERY_LIMIT}
          name="q"
          onChange={(event) => onQueryChange(event.target.value)}
          placeholder="Search by words, a name, or a date"
          ref={field}
          size="large"
          trailing={
            query ? (
              <IconButton
                label="Clear search"
                onClick={() => {
                  setQuery("");
                  go({ query: "" }, "replace");
                  field.current?.focus();
                }}
                size="small"
                type="button"
              >
                <Icon name="close" size={14} />
              </IconButton>
            ) : null
          }
          value={query}
        />
        {/* Without JavaScript, submitting keeps the filters already chosen. */}
        {request.itemClassifications.map((value) => (
          <input key={value} name="type" type="hidden" value={value} />
        ))}
        {request.tagNames.map((name) => (
          <input key={name} name="tag" type="hidden" value={name} />
        ))}
        {request.dateFrom ? (
          <input name="from" type="hidden" value={request.dateFrom} />
        ) : null}
        {request.dateTo ? (
          <input name="to" type="hidden" value={request.dateTo} />
        ) : null}
      </form>

      <div className={styles.filterBar}>
        <SegmentedControl<Show>
          className={styles.show}
          label="Show"
          name="show"
          onChange={(value) =>
            go({ itemClassifications: value ? [value] : [] })
          }
          options={showOptions}
          value={show}
        />
        <div className={styles.filterButtons}>
          <Button
            aria-controls={panel === "tags" ? panelId : undefined}
            aria-expanded={panel === "tags"}
            className={styles.filterButton}
            data-active={request.tagNames.length ? "true" : undefined}
            onClick={() => setPanel(panel === "tags" ? null : "tags")}
            size="small"
            variant="ghost"
          >
            {request.tagNames.length
              ? `Tags · ${request.tagNames.length}`
              : "Tags"}
          </Button>
          <Button
            aria-controls={panel === "dates" ? panelId : undefined}
            aria-expanded={panel === "dates"}
            className={styles.filterButton}
            data-active={datesActive ? "true" : undefined}
            onClick={() => setPanel(panel === "dates" ? null : "dates")}
            size="small"
            variant="ghost"
          >
            {datesActive ? "Dates · 1" : "Dates"}
          </Button>
          {request.hasCriteria ? (
            <ButtonLink
              className={styles.clearAll}
              href="/library"
              scroll={false}
              size="small"
              variant="ghost"
            >
              Clear all
            </ButtonLink>
          ) : null}
        </div>
      </div>

      {panel === "tags" ? (
        <div
          aria-label="Tags"
          className={styles.panel}
          id={panelId}
          role="group"
        >
          {tagOptions.length ? (
            <ul className={styles.tagList}>
              {tagOptions.map((name) => (
                <li key={name.toLocaleLowerCase()}>
                  <button
                    aria-pressed={selectedTags.has(name.toLocaleLowerCase())}
                    className={styles.tagOption}
                    onClick={() => toggleTag(name)}
                    type="button"
                  >
                    #{name}
                  </button>
                </li>
              ))}
            </ul>
          ) : (
            <p className={styles.panelNote}>
              No tags yet. Add tags to an Entry to filter by them here.
            </p>
          )}
        </div>
      ) : null}

      {panel === "dates" ? (
        <DateFilters
          onApply={(dateFrom, dateTo) => go({ dateFrom, dateTo })}
          panelId={panelId}
          request={request}
        />
      ) : null}

      {children}
    </div>
  );
}

/**
 * From and To dates that apply as soon as they form a valid period, so there is no extra button
 * to press. Clearing a date removes it.
 */
function DateFilters({
  onApply,
  panelId,
  request,
}: {
  onApply: (dateFrom: string | null, dateTo: string | null) => void;
  panelId: string;
  request: SearchRequest;
}) {
  const [from, setFrom] = useState(request.dateFrom ?? "");
  const [to, setTo] = useState(request.dateTo ?? "");
  const [notice, setNotice] = useState<string | null>(null);
  // A new address, such as Clear all or Back, resets the fields to its dates.
  const applied = `${request.dateFrom ?? ""}:${request.dateTo ?? ""}`;
  const [shownDates, setShownDates] = useState(applied);
  if (shownDates !== applied) {
    setShownDates(applied);
    setFrom(request.dateFrom ?? "");
    setTo(request.dateTo ?? "");
    setNotice(null);
  }

  function update(nextFrom: string, nextTo: string) {
    setFrom(nextFrom);
    setTo(nextTo);
    const complete = (value: string) => value === "" || isISODate(value);
    if (!complete(nextFrom) || !complete(nextTo)) {
      setNotice(null);
      return;
    }
    if (nextFrom && nextTo && nextFrom > nextTo) {
      setNotice("The start date must be on or before the end date.");
      return;
    }
    setNotice(null);
    if (
      (nextFrom || null) !== request.dateFrom ||
      (nextTo || null) !== request.dateTo
    ) {
      onApply(nextFrom || null, nextTo || null);
    }
  }

  return (
    <div aria-label="Dates" className={styles.panel} id={panelId} role="group">
      <div className={styles.dateFields}>
        <DatePickerField
          label="From"
          name="from"
          onChange={(value) => update(value, to)}
          size="small"
          value={from}
        />
        <DatePickerField
          label="To"
          name="to"
          onChange={(value) => update(from, value)}
          size="small"
          value={to}
        />
      </div>
      {notice ? (
        <p className={styles.panelNotice} role="status">
          {notice}
        </p>
      ) : null}
    </div>
  );
}
