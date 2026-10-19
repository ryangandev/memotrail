"use client";

import { useEffect } from "react";
import { Icon } from "@/components/icon";

export function SearchShortcutButton({
  className,
  onOpen,
}: {
  className: string;
  onOpen: () => void;
}) {
  useEffect(() => {
    function handleShortcut(event: KeyboardEvent) {
      if (
        event.defaultPrevented ||
        event.key.toLocaleLowerCase() !== "k" ||
        (!event.metaKey && !event.ctrlKey) ||
        event.altKey ||
        isEditableTarget(event.target)
      ) {
        return;
      }

      event.preventDefault();
      onOpen();
    }

    window.addEventListener("keydown", handleShortcut);
    return () => window.removeEventListener("keydown", handleShortcut);
  }, [onOpen]);

  return (
    <button
      aria-keyshortcuts="Meta+K Control+K"
      aria-haspopup="dialog"
      className={className}
      onClick={onOpen}
      title="Search everything (⌘ K / Ctrl+K)"
      type="button"
    >
      <Icon name="search" />
      <span data-dock-label>Search everything</span>
      <kbd aria-hidden="true">⌘ K</kbd>
    </button>
  );
}

function isEditableTarget(target: EventTarget | null) {
  return (
    target instanceof HTMLElement &&
    (target.isContentEditable || Boolean(target.closest("input, textarea")))
  );
}
