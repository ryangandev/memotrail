"use client";

import { useState } from "react";
import { notify } from "@/components/app-toast";
import { Badge } from "@/components/badge";
import { Button } from "@/components/button";
import { useCaptureQueue } from "@/components/capture-provider";
import { useConfirmationDialog } from "@/components/confirmation-dialog";
import entryFormStyles from "@/components/entry-form.module.css";
import entryListStyles from "@/components/entry-list.module.css";
import { Icon } from "@/components/icon";
import { countLabel } from "@/lib/count-label";
import {
  queuedOccurrence,
  type QueuedInboxEntry,
} from "@/lib/data/inbox-queue";
import type { PendingCapture } from "@/lib/data/inbox-sync";
import { occurrenceLabel } from "@/lib/data/occurrence";
import styles from "./pending-captures.module.css";

/**
 * Captures saved on this device that have not reached MemoTrail yet, including
 * any MemoTrail rejected, which keep their content until the person discards them.
 */
export function PendingCaptureList({
  items,
}: {
  items: readonly PendingCapture[];
}) {
  return (
    <div className={entryListStyles.entryList}>
      {items.map(({ entry, rejection, status }) => (
        <article
          className={styles.pendingEntryCard}
          data-status={status}
          key={entry.id}
        >
          <div className={entryFormStyles.entryMeta}>
            <time dateTime={entry.occurredAt ?? undefined}>
              {occurrenceLabel(queuedOccurrence(entry))}
            </time>
            {status === "rejected" ? (
              <Badge tone="warm">Not accepted</Badge>
            ) : status === "syncing" ? (
              <Badge tone="neutral">Syncing…</Badge>
            ) : (
              <Badge>On this device</Badge>
            )}
          </div>
          <h3>{entry.title ?? "Untitled Entry"}</h3>
          {entry.body ? <p>{entry.body}</p> : null}
          {entry.attachments.length > 0 ? (
            <span className={styles.pendingPhotoCount}>
              <Icon name="photo" size={14} />
              {countLabel(entry.attachments.length, "photo")}
            </span>
          ) : null}
          {rejection ? (
            <RejectedCapture entry={entry} message={rejection.message} />
          ) : null}
        </article>
      ))}
    </div>
  );
}

/** Why MemoTrail refused a capture, with the ways to keep or remove it. */
function RejectedCapture({
  entry,
  message,
}: {
  entry: QueuedInboxEntry;
  message: string;
}) {
  const { discard } = useCaptureQueue();
  const requestConfirmation = useConfirmationDialog();
  const [isDiscarding, setIsDiscarding] = useState(false);
  const text = [entry.title, entry.body].filter(Boolean).join("\n\n");

  async function copyText() {
    try {
      await navigator.clipboard.writeText(text);
      notify.success("Text copied.");
    } catch {
      notify.error("This browser could not copy the text.");
    }
  }

  async function discardCapture() {
    const confirmed = await requestConfirmation({
      title: <>Discard this pending Entry?</>,
      description: (
        <>
          Its {entry.attachments.length > 0 ? "text and photos" : "text"} will
          be removed from this device. This cannot be undone.
        </>
      ),
      confirmLabel: "Discard",
      eyebrow: <>Permanent action</>,
      variant: "danger",
    });
    if (!confirmed) return;

    setIsDiscarding(true);
    const discarded = await discard(entry.id);
    setIsDiscarding(false);
    if (discarded) notify.info("Pending Entry discarded.");
    else
      notify.error(
        "MemoTrail could not discard this Entry from this device. Try again.",
      );
  }

  return (
    <div className={styles.pendingRejection}>
      <p>{message}</p>
      <div className={styles.pendingRejectionActions}>
        {text ? (
          <Button
            disabled={isDiscarding}
            onClick={() => void copyText()}
            size="small"
            variant="secondary"
          >
            <Icon name="copy" size={14} />
            Copy text
          </Button>
        ) : null}
        <Button
          loading={isDiscarding}
          onClick={() => void discardCapture()}
          size="small"
          variant="danger"
        >
          <Icon name="trash" size={14} />
          Discard
        </Button>
      </div>
    </div>
  );
}
