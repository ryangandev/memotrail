"use client";

import { Button, ButtonLink } from "@/components/button";
import { countLabel } from "@/lib/count-label";
import type { ImportJobView, ImportProgress } from "@/lib/import/contracts";
import { importResultReasonLabel } from "@/lib/import/contracts";
import { sourceLabel } from "@/lib/import/labels";
import { importMarkerTag } from "@/lib/import/tags";
import styles from "@/components/import-workspace.module.css";

/** What an import did, and what can still be done about it. */
export function ImportResult({
  busy,
  job,
  onDone,
  onReport,
  onRetry,
  onUndo,
  progress,
}: {
  busy: boolean;
  job: ImportJobView;
  progress: ImportProgress | null;
  onDone: () => void;
  onReport: () => void;
  onRetry: () => void;
  onUndo: () => void;
}) {
  const items = progress?.items ?? {};
  const created = (items.imported ?? 0) + (items.partial ?? 0);
  const unchanged = items.unchanged ?? 0;
  const skipped = items.skipped ?? 0;
  const failed = items.failed ?? 0;
  const photos = progress?.photos ?? { failed: 0, imported: 0, skipped: 0 };
  const reasons = Object.entries(progress?.reasons ?? {}).filter(
    ([, count]) => (count ?? 0) > 0,
  );
  const trouble = failed + (items.partial ?? 0) > 0;
  const marker = job.options.tags?.marker ? importMarkerTag(job.source) : null;

  return (
    <>
      <section aria-labelledby="import-result" className={styles.card}>
        <h2 id="import-result">
          {trouble ? "Import finished, with some problems" : "Import finished"}
        </h2>
        <p>
          {sourceLabel(job.source)} · {job.fileName}
        </p>
        <dl className={styles.stats}>
          <div className={styles.stat}>
            <dt>New Entries</dt>
            <dd>{created}</dd>
          </div>
          <div className={styles.stat}>
            <dt>Photos added</dt>
            <dd>{photos.imported}</dd>
          </div>
          {unchanged > 0 ? (
            <div className={styles.stat}>
              <dt>Already there</dt>
              <dd>{unchanged}</dd>
            </div>
          ) : null}
          {skipped > 0 ? (
            <div className={styles.stat}>
              <dt>Skipped</dt>
              <dd>{skipped}</dd>
            </div>
          ) : null}
          {failed > 0 ? (
            <div className={styles.stat}>
              <dt>Not imported</dt>
              <dd>{failed}</dd>
            </div>
          ) : null}
        </dl>
        {reasons.length > 0 ? (
          <ul className={styles.breakdown}>
            {reasons.map(([reason, count]) => (
              <li key={reason}>
                {count} · {importResultReasonLabel(reason)}
              </li>
            ))}
          </ul>
        ) : null}
        {photos.failed > 0 ? (
          <p className={styles.notice} data-tone="warning">
            {countLabel(photos.failed, "photo")} did not upload. Retry the ones
            that failed to add them to their Entries.
          </p>
        ) : null}
        <div className={styles.actions}>
          {marker ? (
            <ButtonLink
              href={`/library?tag=${encodeURIComponent(marker)}`}
              variant="primary"
            >
              See them in Library
            </ButtonLink>
          ) : (
            <ButtonLink href="/library" variant="primary">
              Open Library
            </ButtonLink>
          )}
          {trouble && job.staged ? (
            <Button disabled={busy} onClick={onRetry} variant="secondary">
              Retry what failed
            </Button>
          ) : null}
          <Button disabled={busy} onClick={onReport} variant="secondary">
            Download report
          </Button>
        </div>
        <p className={styles.footnote}>
          The report lists what was not imported and why. It has no titles or
          text from your notes.
        </p>
      </section>
      <section aria-labelledby="import-after" className={styles.card}>
        <h2 id="import-after">After this import</h2>
        <p>
          Imported Entries are ordinary Entries. You can edit them, tag them,
          and export them like any other.
        </p>
        <div className={styles.actions}>
          <Button disabled={busy} onClick={onDone} variant="secondary">
            Import another file
          </Button>
          {created > 0 ? (
            <Button disabled={busy} onClick={onUndo} variant="secondary">
              Undo this import
            </Button>
          ) : null}
        </div>
        {created > 0 ? (
          <p className={styles.footnote}>
            Undo moves the Entries from this import to Trash, except any you
            have edited since. It is available for 30 days.
          </p>
        ) : null}
      </section>
    </>
  );
}
