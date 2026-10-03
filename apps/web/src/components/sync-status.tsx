"use client";
import syncStatusStyles from "@/components/sync-status.module.css";

import { useState } from "react";
import { Button } from "@/components/button";
import { useCaptureQueue } from "@/components/capture-provider";
import { Dialog } from "@/components/dialog";
import { Icon } from "@/components/icon";
import { PendingCaptureList } from "@/components/pending-captures";
import { countLabel } from "@/lib/count-label";
import { hasWaitingCaptures } from "@/lib/data/inbox-sync";

/** The workspace's pending captures: syncs them and lists what is waiting. */
export function SyncStatus() {
  const captureQueue = useCaptureQueue();
  const { isSyncing, items, lastError, synchronize } = captureQueue;
  const [isOpen, setIsOpen] = useState(false);
  const isVisible = hasWaitingCaptures(captureQueue);

  // Once everything syncs, the list closes with its indicator.
  if (isOpen && items.length === 0) setIsOpen(false);

  if (!isVisible && !isOpen) {
    return null;
  }

  return (
    <Dialog
      description={`${countLabel(items.length, "Entry")} saved on this device will sync when MemoTrail can be reached.`}
      footer={
        <Button
          disabled={isSyncing}
          onClick={() => void synchronize()}
          type="button"
          variant="secondary"
        >
          <Icon name="refresh" size={14} />
          {isSyncing ? "Syncing…" : "Retry now"}
        </Button>
      }
      onOpenChange={setIsOpen}
      open={isOpen}
      size="compact"
      title="Pending sync"
      trigger={
        <button
          aria-busy={isSyncing}
          className={syncStatusStyles.syncStatus}
          onClick={() => void synchronize()}
          title="Sync now and review captures waiting on this device"
          type="button"
        >
          <span aria-hidden="true" />
          {items.length} pending
        </button>
      }
    >
      {lastError ? (
        <p className={syncStatusStyles.syncError} role="alert">
          {lastError}
        </p>
      ) : null}
      <PendingCaptureList items={items} />
    </Dialog>
  );
}
