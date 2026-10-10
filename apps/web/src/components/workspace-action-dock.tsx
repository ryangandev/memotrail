"use client";

import type { ReactNode } from "react";
import { SearchShortcutButton } from "@/components/search-shortcut-link";
import styles from "./workspace-action-dock.module.css";

/**
 * The floating glass dock that holds Quick Capture and the search shortcut.
 * Specified in packages/design-system/components/workspace-action-dock.yaml.
 */
export function WorkspaceActionDock({
  children,
  onSearch,
}: {
  children: ReactNode;
  onSearch: () => void;
}) {
  return (
    <div
      className={styles.dock}
      data-capture-dock
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
