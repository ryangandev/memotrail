"use client";

import { useRouter } from "next/navigation";
import { useEffect, useMemo, useState } from "react";
import { Icon, type IconName } from "@/components/icon";
import { SearchField } from "@/components/search-field";
import {
  parseQuickSearchResult,
  type QuickSearchResult,
} from "@/lib/data/search-input";
import styles from "./command-palette.module.css";

type Command = {
  description: string;
  href: string;
  icon: IconName;
  keywords: string;
  label: string;
};

type PaletteItem = Omit<Command, "keywords"> & { key: string };
type SearchState = QuickSearchResult & { query: string };

const commands: Command[] = [
  {
    description: "Open full search with filters and AI",
    href: "/search",
    icon: "search",
    keywords: "find advanced filter ai",
    label: "Search page",
  },
  {
    description: "Return to your recent story",
    href: "/",
    icon: "home",
    keywords: "recent story",
    label: "Home",
  },
  {
    description: "Review newly captured Entries",
    href: "/inbox",
    icon: "inbox",
    keywords: "review capture entries",
    label: "Inbox",
  },
  {
    description: "Move through your story over time",
    href: "/timeline",
    icon: "timeline",
    keywords: "life story dates moments",
    label: "Timeline",
  },
  {
    description: "Browse every part of your archive",
    href: "/library",
    icon: "archive",
    keywords: "records archive",
    label: "Library",
  },
  {
    description: "Browse your curated chapters",
    href: "/collections",
    icon: "archive",
    keywords: "chapters organize",
    label: "Collections",
  },
  {
    description: "Browse lightweight archive filters",
    href: "/tags",
    icon: "tag",
    keywords: "labels filter organize",
    label: "Tags",
  },
  {
    description: "Manage account and preferences",
    href: "/settings",
    icon: "settings",
    keywords: "account preference timezone",
    label: "Settings",
  },
];

const emptySearchState: SearchState = {
  error: null,
  items: [],
  query: "",
};

export function CommandPalette({
  onClose,
  open,
}: {
  onClose: () => void;
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
      description: `${item.label} · ${item.subtitle}`,
      href: item.href,
      icon: quickResultIcon(item.kind),
      key: `${item.kind}:${item.id}`,
      label: item.title,
    }),
  );
  const navigationItems: PaletteItem[] = filteredCommands.map((command) => ({
    description: command.description,
    href: command.href,
    icon: command.icon,
    key: `command:${command.href}`,
    label: command.label,
  }));
  const fullSearchItem: PaletteItem | null = normalizedQuery
    ? {
        description: "Use filters or ask AI on the full Search page",
        href: `/search?q=${encodeURIComponent(normalizedQuery)}`,
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
          error: "MemoTrail could not search your archive. Try again.",
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
    router.push(item.href);
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
        role="dialog"
      >
        <h2 id="command-palette-title" className={styles.visuallyHidden}>
          Search MemoTrail
        </h2>
        <div className={styles.searchRow}>
          <SearchField
            autoFocus
            hideLabel
            label="Search your archive"
            maxLength={200}
            onChange={(event) => {
              setQuery(event.target.value);
              setActiveIndex(0);
            }}
            onKeyDown={handleInputKeyDown}
            placeholder="Search your archive or jump somewhere..."
            size="large"
            trailing={<kbd aria-hidden="true">esc</kbd>}
            value={query}
          />
        </div>

        <div className={styles.resultsViewport}>
          {normalizedQuery ? (
            <div className={styles.section}>
              <p className={styles.sectionLabel} aria-live="polite">
                {searching ? "Searching your trail..." : "Archive results"}
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
                  <span />
                  <span />
                  <span />
                </div>
              ) : (
                <p className={styles.empty}>No archive matches yet.</p>
              )}
            </div>
          ) : null}

          {navigationItems.length ? (
            <div className={styles.section}>
              <p className={styles.sectionLabel}>
                {normalizedQuery ? "Navigation" : "Quick navigation"}
              </p>
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

function quickResultIcon(kind: "entry" | "person" | "place"): IconName {
  if (kind === "place") return "map";
  if (kind === "person") return "archive";
  return "timeline";
}
