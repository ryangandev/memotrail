"use client";

import { useRouter } from "next/navigation";
import { useEffect, useMemo, useState } from "react";
import { Icon, type IconName } from "@/components/icon";
import { SearchField } from "@/components/search-field";
import { Skeleton } from "@/components/skeleton";
import {
  parseQuickSearchResult,
  type QuickSearchResult,
} from "@/lib/data/search-input";
import { quickResultDescription } from "@/lib/search/match-presentation";
import styles from "./command-palette.module.css";

type Command = {
  description: string;
  icon: IconName;
  keywords: string;
  label: string;
} & ({ href: string; action?: never } | { action: "new-entry"; href?: never });

type PaletteItem = {
  action?: "new-entry";
  description: string;
  href?: string;
  icon: IconName;
  key: string;
  label: string;
};
type SearchState = QuickSearchResult & { query: string };

const commands: Command[] = [
  {
    action: "new-entry",
    description: "Write something down",
    icon: "plus",
    keywords: "new entry capture write add create note memory",
    label: "New Entry",
  },
  {
    description: "Today, and what you wrote lately",
    href: "/",
    icon: "dashboard",
    keywords: "home today recent",
    label: "Dashboard",
  },
  {
    description: "Your Chapters and Entries across the years",
    href: "/timeline",
    icon: "timeline",
    keywords: "life chapters dates years",
    label: "Timeline",
  },
  {
    description: "Every Entry, with search and filters",
    href: "/library",
    icon: "archive",
    keywords: "entries search find filter",
    label: "Library",
  },
  {
    description: "The things you did for the first time",
    href: "/first-times",
    icon: "star",
    keywords: "firsts beginnings photos",
    label: "First Times",
  },
  {
    description: "Year and Chapter reviews to return to",
    href: "/reviews",
    icon: "quote",
    keywords: "year review chapter return look back",
    label: "Reviews",
  },
  {
    description: "Name and tidy your tags",
    href: "/tags",
    icon: "tag",
    keywords: "labels organize groups",
    label: "Tags",
  },
  {
    description: "Bring in notes from another app",
    href: "/settings/import",
    icon: "inbox",
    keywords: "import markdown day one notes bring",
    label: "Import",
  },
  {
    description: "Download a copy of everything",
    href: "/settings/export",
    icon: "archive",
    keywords: "export download backup copy",
    label: "Export",
  },
  {
    description: "Restore Entries or delete them for good",
    href: "/trash",
    icon: "trash",
    keywords: "deleted restore recover remove",
    label: "Trash",
  },
  {
    description: "Profile, Timeline, appearance, AI, and account",
    href: "/settings",
    icon: "settings",
    keywords: "account preferences timezone appearance theme profile",
    label: "Settings",
  },
];

const emptySearchState: SearchState = {
  error: null,
  items: [],
  query: "",
};

/**
 * The keyboard-first search over Entries, the workspace's destinations, and New Entry.
 * Specified in packages/design-system/components/command-palette.yaml.
 */
export function CommandPalette({
  onClose,
  onNewEntry,
  open,
}: {
  onClose: () => void;
  /** Opens Quick Capture, for the New Entry command. */
  onNewEntry: () => void;
  open: boolean;
}) {
  const router = useRouter();
  const [activeIndex, setActiveIndex] = useState(0);
  const [debouncedQuery, setDebouncedQuery] = useState("");
  const [query, setQuery] = useState("");
  const [searchState, setSearchState] = useState(emptySearchState);
  const normalizedQuery = query.trim();
  const filteredCommands = useMemo(
    () => filterCommands(normalizedQuery),
    [normalizedQuery],
  );
  const resolvedSearch =
    normalizedQuery && searchState.query === normalizedQuery
      ? searchState
      : null;
  const searchItems: PaletteItem[] = (resolvedSearch?.items ?? []).map(
    (item) => ({
      description: quickResultDescription(item),
      href: item.href,
      icon: "timeline",
      key: `entry:${item.id}`,
      label: item.title,
    }),
  );
  const navigationItems: PaletteItem[] = filteredCommands.map((command) => ({
    action: command.action,
    description: command.description,
    href: command.href,
    icon: command.icon,
    key: `command:${command.action ?? command.href}`,
    label: command.label,
  }));
  const fullSearchItem: PaletteItem | null = normalizedQuery
    ? {
        description: "Search the Library with filters",
        href: `/library?q=${encodeURIComponent(normalizedQuery)}`,
        icon: "search",
        key: "full-search",
        label: `Search all for “${normalizedQuery}”`,
      }
    : null;
  const paletteItems = fullSearchItem
    ? [...searchItems, ...navigationItems, fullSearchItem]
    : navigationItems;
  const selectedIndex = Math.min(activeIndex, paletteItems.length - 1);
  const searching = Boolean(normalizedQuery && !resolvedSearch);

  useEffect(() => {
    const timeout = window.setTimeout(
      () => setDebouncedQuery(normalizedQuery),
      250,
    );
    return () => window.clearTimeout(timeout);
  }, [normalizedQuery]);

  useEffect(() => {
    if (!debouncedQuery) return;

    const controller = new AbortController();
    const requestQuery = debouncedQuery;

    void fetch(`/api/search/quick?q=${encodeURIComponent(requestQuery)}`, {
      headers: { Accept: "application/json" },
      signal: controller.signal,
    })
      .then(async (response) => {
        const result = parseQuickSearchResult(await response.json());
        if (!response.ok || !result) {
          throw new Error("Quick search response was unavailable.");
        }
        return result;
      })
      .then((result) => {
        setSearchState({ ...result, query: requestQuery });
      })
      .catch((error: unknown) => {
        if (error instanceof DOMException && error.name === "AbortError")
          return;
        setSearchState({
          error: "MemoTrail could not search your Entries. Try again.",
          items: [],
          query: requestQuery,
        });
      });

    return () => controller.abort();
  }, [debouncedQuery]);

  useEffect(() => {
    if (!open) return;

    function handleEscape(event: KeyboardEvent) {
      if (event.key !== "Escape") return;
      event.preventDefault();
      onClose();
    }

    window.addEventListener("keydown", handleEscape);
    return () => window.removeEventListener("keydown", handleEscape);
  }, [onClose, open]);

  if (!open) return null;

  function navigate(item: PaletteItem) {
    onClose();
    if (item.action === "new-entry") onNewEntry();
    else if (item.href) router.push(item.href);
  }

  function handleInputKeyDown(event: React.KeyboardEvent<HTMLInputElement>) {
    if (event.key === "ArrowDown") {
      event.preventDefault();
      setActiveIndex((index) =>
        paletteItems.length ? (index + 1) % paletteItems.length : 0,
      );
      return;
    }

    if (event.key === "ArrowUp") {
      event.preventDefault();
      setActiveIndex((index) =>
        paletteItems.length
          ? (index - 1 + paletteItems.length) % paletteItems.length
          : 0,
      );
      return;
    }

    if (event.key === "Enter" && paletteItems[selectedIndex]) {
      event.preventDefault();
      navigate(paletteItems[selectedIndex]);
    }
  }

  function itemRow(item: PaletteItem, index: number) {
    return (
      <button
        aria-current={index === selectedIndex ? "true" : undefined}
        className={`${styles.command} ${
          index === selectedIndex ? styles.commandActive : ""
        }`}
        key={item.key}
        onClick={() => navigate(item)}
        onMouseEnter={() => setActiveIndex(index)}
        type="button"
      >
        <span>
          <Icon name={item.icon} size={18} />
        </span>
        <span>
          <strong>{item.label}</strong>
          <small>{item.description}</small>
        </span>
        <Icon name="chevron" size={15} />
      </button>
    );
  }

  return (
    <div
      className={styles.backdrop}
      onMouseDown={(event) => {
        if (event.currentTarget === event.target) onClose();
      }}
    >
      <section
        aria-labelledby="command-palette-title"
        aria-modal="true"
        className={styles.dialog}
        data-ui-command-palette
        role="dialog"
      >
        <h2 id="command-palette-title" className={styles.visuallyHidden}>
          Search MemoTrail
        </h2>
        <div className={styles.searchRow}>
          <SearchField
            autoFocus
            hideLabel
            label="Search MemoTrail"
            maxLength={200}
            onChange={(event) => {
              setQuery(event.target.value);
              setActiveIndex(0);
            }}
            onKeyDown={handleInputKeyDown}
            placeholder="Search Entries or go somewhere..."
            size="large"
            trailing={<kbd aria-hidden="true">esc</kbd>}
            value={query}
          />
        </div>

        <div className={styles.resultsViewport}>
          {normalizedQuery ? (
            <div className={styles.section}>
              <p className={styles.sectionLabel} aria-live="polite">
                {searching ? "Searching..." : "Entries"}
              </p>
              {resolvedSearch?.error ? (
                <p className={styles.notice} role="status">
                  {resolvedSearch.error}
                </p>
              ) : null}
              {searchItems.length ? (
                <div className={styles.commandList}>
                  {searchItems.map((item, index) => itemRow(item, index))}
                </div>
              ) : searching ? (
                <div className={styles.searching} aria-hidden="true">
                  <Skeleton height="44px" />
                  <Skeleton height="44px" />
                  <Skeleton height="44px" />
                </div>
              ) : (
                <p className={styles.empty}>No Entries match yet.</p>
              )}
            </div>
          ) : null}

          {navigationItems.length ? (
            <div className={styles.section}>
              <p className={styles.sectionLabel}>Go to</p>
              <div className={styles.commandList}>
                {navigationItems.map((item, index) =>
                  itemRow(item, searchItems.length + index),
                )}
              </div>
            </div>
          ) : null}

          {fullSearchItem ? (
            <div className={`${styles.section} ${styles.fullSearchSection}`}>
              {itemRow(
                fullSearchItem,
                searchItems.length + navigationItems.length,
              )}
            </div>
          ) : null}
        </div>

        <footer className={styles.footer}>
          <span>
            <kbd>↑</kbd>
            <kbd>↓</kbd>
            to navigate
          </span>
          <span>
            <kbd>↵</kbd>
            to open
          </span>
        </footer>
      </section>
    </div>
  );
}

function filterCommands(query: string) {
  const terms = query.toLocaleLowerCase().split(/\s+/).filter(Boolean);
  if (terms.length === 0) return commands;

  return commands.filter((command) => {
    const searchValue =
      `${command.label} ${command.description} ${command.keywords}`.toLocaleLowerCase();
    return terms.every((term) => searchValue.includes(term));
  });
}
