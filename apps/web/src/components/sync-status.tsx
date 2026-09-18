"use client";
import syncStatusStyles from "@/components/sync-status.module.css";

import { useEffect, useState } from "react";
import { inboxQueueChangedEvent, loadInboxQueue } from "@/lib/data/inbox-queue";

type QueueChangedDetail = {
  count: number;
  ownerId: string;
};

export function SyncStatus({ ownerId }: { ownerId: string }) {
  const [pendingCount, setPendingCount] = useState(0);

  useEffect(() => {
    let isCanceled = false;

    queueMicrotask(() => {
      if (!isCanceled) {
        setPendingCount(loadInboxQueue(window.localStorage, ownerId).length);
      }
    });

    function handleQueueChanged(event: Event) {
      const detail = (event as CustomEvent<QueueChangedDetail>).detail;

      if (detail?.ownerId === ownerId) {
        setPendingCount(detail.count);
      }
    }

    window.addEventListener(inboxQueueChangedEvent, handleQueueChanged);

    return () => {
      isCanceled = true;
      window.removeEventListener(inboxQueueChangedEvent, handleQueueChanged);
    };
  }, [ownerId]);

  if (!pendingCount) {
    return null;
  }

  return (
    <span
      aria-live="polite"
      className={syncStatusStyles.syncStatus}
      role="status"
    >
      <span />
      {pendingCount} pending
    </span>
  );
}
