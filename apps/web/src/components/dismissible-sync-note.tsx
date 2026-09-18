"use client";
import { Button } from "@/components/button";

import { useCallback, useState, useSyncExternalStore } from "react";
import styles from "@/app/page.module.css";
import { Icon } from "@/components/icon";

export function DismissibleSyncNote({ ownerId }: { ownerId: string }) {
  const [dismissedForSession, setDismissedForSession] = useState(false);
  const storageKey = `memotrail:${ownerId}:private-cloud-sync-dismissed`;
  const subscribe = useCallback((onStoreChange: () => void) => {
    window.addEventListener("storage", onStoreChange);
    window.addEventListener("memotrail:sync-note-change", onStoreChange);

    return () => {
      window.removeEventListener("storage", onStoreChange);
      window.removeEventListener("memotrail:sync-note-change", onStoreChange);
    };
  }, []);
  const getSnapshot = useCallback(() => {
    try {
      return window.localStorage.getItem(storageKey) === "true";
    } catch {
      return false;
    }
  }, [storageKey]);
  const dismissed = useSyncExternalStore(
    subscribe,
    getSnapshot,
    serverDismissedSnapshot,
  );

  function dismiss() {
    setDismissedForSession(true);

    try {
      window.localStorage.setItem(storageKey, "true");
    } catch {
      // The note can still be dismissed for this session when storage is blocked.
    }

    window.dispatchEvent(new Event("memotrail:sync-note-change"));
  }

  if (dismissed || dismissedForSession) return null;

  return (
    <div
      aria-label="Private cloud sync"
      className={styles.archiveNote}
      role="note"
    >
      <Icon name="clock" size={17} />
      <div>
        <strong>Private cloud sync</strong>
        <span>Available on Web and iPhone</span>
      </div>
      <Button
        variant="secondary"
        aria-label="Dismiss private cloud sync"
        onClick={dismiss}
        title="Dismiss"
        type="button"
      >
        <Icon name="close" size={15} />
      </Button>
    </div>
  );
}

function serverDismissedSnapshot() {
  return true;
}
