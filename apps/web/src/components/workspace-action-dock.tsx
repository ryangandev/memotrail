"use client";

import type { ReactNode } from "react";
import { SearchShortcutButton } from "@/components/search-shortcut-link";
import styles from "./workspace-action-dock.module.css";

export function WorkspaceActionDock({
  children,
  onSearch,
}: {
  children: ReactNode;
  onSearch: () => void;
}) {
  return (
    <div className={styles.dock} data-capture-dock>
      {children}
      <SearchShortcutButton
        className={`${styles.control} ${styles.search}`}
        onOpen={onSearch}
      />
    </div>
  );
}
