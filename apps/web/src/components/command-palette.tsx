"use client";

import { useRouter } from "next/navigation";
import { useEffect, useMemo, useState } from "react";
import { Icon, type IconName } from "@/components/icon";
import styles from "./command-palette.module.css";

type Command = {
  description: string;
  href: string;
  icon: IconName;
  keywords: string;
  label: string;
};

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

export function CommandPalette({
  onClose,
  open,
}: {
  onClose: () => void;
  open: boolean;
}) {
  const router = useRouter();
  const [activeIndex, setActiveIndex] = useState(0);
  const [query, setQuery] = useState("");
  const filteredCommands = useMemo(() => {
    const terms = query.trim().toLocaleLowerCase().split(/\s+/).filter(Boolean);
    if (terms.length === 0) return commands;

    return commands.filter((command) => {
      const searchValue = `${command.label} ${command.description} ${command.keywords}`.toLocaleLowerCase();
      return terms.every((term) => searchValue.includes(term));
    });
  }, [query]);
  const selectedIndex = Math.min(activeIndex, filteredCommands.length - 1);

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

  function navigate(command: Command) {
    onClose();
    router.push(command.href);
  }

  function handleInputKeyDown(event: React.KeyboardEvent<HTMLInputElement>) {
    if (event.key === "ArrowDown") {
      event.preventDefault();
      setActiveIndex((index) =>
        filteredCommands.length ? (index + 1) % filteredCommands.length : 0,
      );
      return;
    }

    if (event.key === "ArrowUp") {
      event.preventDefault();
      setActiveIndex((index) =>
        filteredCommands.length
          ? (index - 1 + filteredCommands.length) % filteredCommands.length
          : 0,
      );
      return;
    }

    if (event.key === "Enter" && filteredCommands[selectedIndex]) {
      event.preventDefault();
      navigate(filteredCommands[selectedIndex]);
    }
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
        <label className={styles.searchField}>
          <Icon name="search" size={22} />
          <span className={styles.visuallyHidden}>Search commands</span>
          <input
            autoFocus
            onChange={(event) => {
              setQuery(event.target.value);
              setActiveIndex(0);
            }}
            onKeyDown={handleInputKeyDown}
            placeholder="Search MemoTrail or jump somewhere..."
            type="search"
            value={query}
          />
          <kbd aria-hidden="true">esc</kbd>
        </label>

        <div className={styles.section}>
          <p className={styles.sectionLabel}>Quick navigation</p>
          {filteredCommands.length ? (
            <div className={styles.commandList}>
              {filteredCommands.map((command, index) => (
                <button
                  aria-current={index === selectedIndex ? "true" : undefined}
                  className={`${styles.command} ${
                    index === selectedIndex ? styles.commandActive : ""
                  }`}
                  key={command.href}
                  onClick={() => navigate(command)}
                  onMouseEnter={() => setActiveIndex(index)}
                  type="button"
                >
                  <span>
                    <Icon name={command.icon} size={18} />
                  </span>
                  <span>
                    <strong>{command.label}</strong>
                    <small>{command.description}</small>
                  </span>
                  <Icon name="chevron" size={15} />
                </button>
              ))}
            </div>
          ) : (
            <p className={styles.empty}>No matching destinations.</p>
          )}
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
