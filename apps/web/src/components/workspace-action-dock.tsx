"use client";

import { usePathname } from "next/navigation";
import type { ReactNode } from "react";
import { SearchShortcutButton } from "@/components/search-shortcut-link";
import styles from "./workspace-action-dock.module.css";

/**
 * The floating glass dock at the bottom of the workspace. It holds the search shortcut, and
 * Quick Capture's trigger beside it on every page but the Dashboard, whose composer is already
 * on the page. Specified in packages/design-system/components/workspace-action-dock.yaml.
 */
export function WorkspaceActionDock({
  children,
  onSearch,
}: {
  children: ReactNode;
  onSearch: () => void;
}) {
  const searchOnly = usePathname() === "/";
  return (
    <div
      className={styles.dock}
      data-capture-dock
      data-search-only={searchOnly ? "true" : undefined}
      data-ui-workspace-action-dock
    >
      {children}
      <SearchShortcutButton
        className={`${styles.control} ${styles.search}`}
        onOpen={onSearch}
      />
    </div>
  );
}
