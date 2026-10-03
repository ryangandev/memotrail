import { Badge } from "@/components/badge";
import entryFormStyles from "@/components/entry-form.module.css";
import entryListStyles from "@/components/entry-list.module.css";
import { Icon } from "@/components/icon";
import { countLabel } from "@/lib/count-label";
import { queuedOccurrence } from "@/lib/data/inbox-queue";
import type { PendingCapture } from "@/lib/data/inbox-sync";
import { occurrenceLabel } from "@/lib/data/occurrence";
import styles from "./pending-captures.module.css";

/** Captures saved on this device that have not reached MemoTrail yet. */
export function PendingCaptureList({
  items,
}: {
  items: readonly PendingCapture[];
}) {
  return (
    <div className={entryListStyles.entryList}>
      {items.map(({ entry, status }) => (
        <article className={styles.pendingEntryCard} key={entry.id}>
          <div className={entryFormStyles.entryMeta}>
            <time dateTime={entry.occurredAt ?? undefined}>
              {occurrenceLabel(queuedOccurrence(entry))}
            </time>
            {status === "syncing" ? (
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
        </article>
      ))}
    </div>
  );
}
