"use client";
import syncStatusStyles from "@/components/sync-status.module.css";

import { useState, type ComponentPropsWithRef } from "react";
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

/**
 * The workspace's pending captures: syncs them and lists what is waiting.
 * Specified in packages/design-system/components/sync-status.yaml.
 */
export function SyncStatus({
  idleLabel,
}: {
  /** Quiet text shown while nothing waits, such as Synced; without it the indicator disappears. */
  idleLabel?: string;
} = {}) {
  const captureQueue = useCaptureQueue();
  const { isSyncing, items, lastError, synchronize, unreadable } = captureQueue;
  const [isOpen, setIsOpen] = useState(false);
  const isVisible = hasWaitingCaptures(captureQueue);
  const { rejected, waiting } = countPendingCaptures(items);

  // Once everything syncs or is discarded, the list closes with its indicator.
  if (isOpen && items.length === 0 && unreadable.length === 0) setIsOpen(false);

  if (!isVisible && !isOpen) {
    return idleLabel ? (
      <span className={syncStatusStyles.idle} data-sync-idle>
        {idleLabel}
      </span>
    ) : null;
  }

  const description = [
    waiting > 0
      ? `${countLabel(waiting, "Entry")} saved on this device will sync when MemoTrail can be reached.`
      : null,
    rejected > 0
      ? `MemoTrail did not accept ${countLabel(rejected, "Entry")}; copy what you want to keep, then discard ${rejected === 1 ? "it" : "them"}.`
      : null,
    unreadable.length > 0
      ? `${countLabel(unreadable.length, "saved Entry")} on this device could not be read; copy what you want to keep, then discard ${unreadable.length === 1 ? "it" : "them"}.`
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
        <SyncStatusButton
          busy={isSyncing}
          onClick={() => void synchronize()}
          rejected={rejected}
          unreadable={unreadable.length}
          waiting={waiting}
        />
      }
    >
      {lastError ? (
        <p className={syncStatusStyles.syncError} role="alert">
          {lastError}
        </p>
      ) : null}
      <PendingCaptureList items={items} unreadable={unreadable} />
    </Dialog>
  );
}

/**
 * The indicator itself, in the sidebar's account row and the phone top bar: the counts of
 * captures waiting on this device and refused by MemoTrail, drawn in the danger color when one
 * was refused. SyncStatus wires it to the capture queue.
 */
export function SyncStatusButton({
  busy,
  rejected,
  unreadable = 0,
  waiting,
  ...props
}: {
  busy: boolean;
  rejected: number;
  /** Saved captures that could not be read; they wait for the person too. */
  unreadable?: number;
  waiting: number;
} & Omit<ComponentPropsWithRef<"button">, "children" | "title" | "type">) {
  const label = [
    waiting > 0 ? `${waiting} pending` : null,
    rejected > 0 ? `${rejected} not accepted` : null,
    unreadable > 0 ? `${unreadable} unreadable` : null,
  ]
    .filter(Boolean)
    .join(" · ");
  return (
    <button
      {...props}
      aria-busy={busy}
      className={syncStatusStyles.syncStatus}
      data-rejected={rejected > 0 || unreadable > 0 || undefined}
      data-ui-sync-status
      title={
        rejected > 0 || unreadable > 0
          ? "Review captures MemoTrail did not accept or could not read, and sync the rest"
          : "Sync now and review captures waiting on this device"
      }
      type="button"
    >
      <span aria-hidden="true" data-sync-dot />
      <span data-sync-label>{label}</span>
    </button>
  );
}
