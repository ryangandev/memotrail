"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect } from "react";
import { Icon } from "@/components/icon";

export function SearchShortcutLink({
  active,
  className,
}: {
  active: boolean;
  className: string;
}) {
  const router = useRouter();

  useEffect(() => {
    function handleShortcut(event: KeyboardEvent) {
      if (
        event.key.toLocaleLowerCase() !== "k" ||
        (!event.metaKey && !event.ctrlKey) ||
        event.altKey
      ) {
        return;
      }

      event.preventDefault();

      if (active) {
        document.getElementById("trail-search")?.focus();
        return;
      }

      router.push("/search");
    }

    window.addEventListener("keydown", handleShortcut);
    return () => window.removeEventListener("keydown", handleShortcut);
  }, [active, router]);

  return (
    <Link aria-label="Search your trail" className={className} href="/search">
      <Icon name="search" />
      <span>{active ? "Search" : "Search your trail"}</span>
      <kbd aria-hidden="true">⌘ K</kbd>
    </Link>
  );
}
