"use client";
import syncStatusStyles from "@/components/sync-status.module.css";

import { useState } from "react";
import { Button } from "@/components/button";
import { useCaptureQueue } from "@/components/capture-provider";
import { Dialog } from "@/components/dialog";
import { Icon } from "@/components/icon";
import { PendingCaptureList } from "@/components/pending-captures";
import { countLabel } from "@/lib/count-label";
import {
  countPendingCaptures,
  hasWaitingCaptures,
} from "@/lib/data/inbox-sync";

/** The workspace's pending captures: syncs them and lists what is waiting. */
export function SyncStatus() {
  const captureQueue = useCaptureQueue();
  const { isSyncing, items, lastError, synchronize } = captureQueue;
  const [isOpen, setIsOpen] = useState(false);
  const isVisible = hasWaitingCaptures(captureQueue);
  const { rejected, waiting } = countPendingCaptures(items);

  // Once everything syncs or is discarded, the list closes with its indicator.
  if (isOpen && items.length === 0) setIsOpen(false);

  if (!isVisible && !isOpen) {
    return null;
  }

  const label = [
    waiting > 0 ? `${waiting} pending` : null,
    rejected > 0 ? `${rejected} not accepted` : null,
  ]
    .filter(Boolean)
    .join(" · ");
  const description = [
    waiting > 0
      ? `${countLabel(waiting, "Entry")} saved on this device will sync when MemoTrail can be reached.`
      : null,
    rejected > 0
      ? `MemoTrail did not accept ${countLabel(rejected, "Entry")}; copy what you want to keep, then discard ${rejected === 1 ? "it" : "them"}.`
      : null,
  ]
    .filter(Boolean)
    .join(" ");

  return (
    <Dialog
      description={description}
      footer={
        waiting > 0 ? (
          <Button
            disabled={isSyncing}
            onClick={() => void synchronize()}
            type="button"
            variant="secondary"
          >
            <Icon name="refresh" size={14} />
            {isSyncing ? "Syncing…" : "Retry now"}
          </Button>
        ) : null
      }
      onOpenChange={setIsOpen}
      open={isOpen}
      size="compact"
      title="Pending sync"
      trigger={
        <button
          aria-busy={isSyncing}
          className={syncStatusStyles.syncStatus}
          data-rejected={rejected > 0 || undefined}
          onClick={() => void synchronize()}
          title={
            rejected > 0
              ? "Review captures MemoTrail did not accept and sync the rest"
              : "Sync now and review captures waiting on this device"
          }
          type="button"
        >
          <span aria-hidden="true" />
          {label}
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
