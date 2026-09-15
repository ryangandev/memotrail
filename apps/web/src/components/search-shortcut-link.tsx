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
      aria-haspopup="dialog"
      aria-label="Search your trail"
      className={className}
      onClick={onOpen}
      type="button"
    >
      <Icon name="search" />
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
