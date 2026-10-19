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
  type UnreadableCapture,
} from "@/lib/data/inbox-queue";
import type { PendingCapture } from "@/lib/data/inbox-sync";
import { entryDisplayTitle, occurrenceLabel } from "@/lib/data/occurrence";
import styles from "./pending-captures.module.css";

/**
 * Captures saved on this device that have not reached MemoTrail yet, including
 * any MemoTrail rejected, which keep their content until the person discards them.
 */
export function PendingCaptureList({
  items,
  unreadable = [],
}: {
  items: readonly PendingCapture[];
  /** Saved captures that could not be read; they are kept until discarded. */
  unreadable?: readonly UnreadableCapture[];
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
            {/* An untitled capture is already named by its date. */}
            {entry.title ? (
              <time dateTime={entry.occurredAt ?? undefined}>
                {occurrenceLabel(queuedOccurrence(entry))}
              </time>
            ) : null}
            {status === "rejected" ? (
              <Badge tone="warm">Not accepted</Badge>
            ) : status === "syncing" ? (
              <Badge tone="neutral">Syncing…</Badge>
            ) : (
              <Badge>On this device</Badge>
            )}
          </div>
          <h3>{entryDisplayTitle(entry.title, queuedOccurrence(entry))}</h3>
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
      {unreadable.map((capture) => (
        <article
          className={styles.pendingEntryCard}
          data-status="rejected"
          key={capture.key}
        >
          <div className={entryFormStyles.entryMeta}>
            <Badge tone="warm">Could not be read</Badge>
          </div>
          <p>{capture.text}</p>
          <UnreadableCaptureActions capture={capture} />
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

/** The ways to keep or remove a saved capture this version cannot read. */
function UnreadableCaptureActions({ capture }: { capture: UnreadableCapture }) {
  const { discardUnreadable } = useCaptureQueue();
  const requestConfirmation = useConfirmationDialog();
  const [isDiscarding, setIsDiscarding] = useState(false);

  async function copyText() {
    try {
      await navigator.clipboard.writeText(capture.text);
      notify.success("Text copied.");
    } catch {
      notify.error("This browser could not copy the text.");
    }
  }

  async function discardCapture() {
    const confirmed = await requestConfirmation({
      title: <>Discard this saved Entry?</>,
      description: (
        <>
          It will be removed from this device, along with any photos it holds.
          This cannot be undone.
        </>
      ),
      confirmLabel: "Discard",
      eyebrow: <>Permanent action</>,
      variant: "danger",
    });
    if (!confirmed) return;

    setIsDiscarding(true);
    const discarded = await discardUnreadable(capture.key);
    setIsDiscarding(false);
    if (discarded) notify.info("Saved Entry discarded.");
    else
      notify.error(
        "MemoTrail could not discard this Entry from this device. Try again.",
      );
  }

  return (
    <div className={styles.pendingRejection}>
      <p>
        This Entry was saved on this device, but this version of MemoTrail
        cannot read it. It is kept until you discard it.
      </p>
      <div className={styles.pendingRejectionActions}>
        <Button
          disabled={isDiscarding}
          onClick={() => void copyText()}
          size="small"
          variant="secondary"
        >
          <Icon name="copy" size={14} />
          Copy text
        </Button>
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
