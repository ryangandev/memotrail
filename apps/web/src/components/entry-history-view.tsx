"use client";
import Link from "next/link";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { restoreHistoryVersion } from "@/app/history/actions";
import {
  historyTitle,
  historyDifferences,
  historyDateLabel,
  type EntryHistory,
  type HistorySnapshot,
} from "@/lib/data/history";
import styles from "@/app/history/page.module.css";
export function EntryHistoryView({
  history,
  page,
}: {
  history: EntryHistory;
  page: number;
}) {
  const router = useRouter();
  const [version, setVersion] = useState(history.versions[0]?.version);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const selected = history.versions.find((v) => v.version === version);
  async function restore() {
    if (
      !selected ||
      !confirm(
        `Restore version ${selected.version}? Your current version will be kept in history. Recorded links and photo membership will also be restored; shared names and definitions, including Collections and tags, stay current.`,
      )
    )
      return;
    setBusy(true);
    setError(null);
    try {
      const message = await restoreHistoryVersion(
        history.current.id,
        selected.version,
        history.current.revision,
      );
      if (message) setError(message);
      else router.refresh();
    } catch {
      setError(
        "Could not confirm restoration. Refresh to check the latest version before trying again.",
      );
    } finally {
      setBusy(false);
    }
  }
  return (
    <>
      <Link href="/history">← All Entry history</Link>
      <h2>{historyTitle(history.current)}</h2>
      {history.versions.length > 0 && (
        <div className={styles.controls}>
          <label>
            Earlier version
            <select
              value={version ?? ""}
              disabled={busy}
              onChange={(e) => setVersion(Number(e.target.value))}
            >
              {history.versions.map((v) => (
                <option key={v.version} value={v.version}>
                  Version {v.version} · saved before{" "}
                  {new Date(v.created_at).toLocaleString()}
                </option>
              ))}
            </select>
          </label>
          <button
            disabled={busy || !selected || Boolean(history.current.deleted_at)}
            onClick={restore}
          >
            {busy ? "Restoring…" : "Restore selected version"}
          </button>
        </div>
      )}
      {history.current.deleted_at && (
        <p role="status">
          This Entry is in Trash. Restore it there before changing its history.
        </p>
      )}
      {error && <p role="alert">{error}</p>}
      {selected && (
        <>
          <p className={styles.notice}>
            Differences from current version:{" "}
            {historyDifferences(history.current, selected.snapshot).join(
              ", ",
            ) || "No recorded content changes"}
            . Your current version {history.current.revision} will stay in
            history.
          </p>
          {selected.snapshot.history_schema !== 2 && (
            <p className={styles.notice}>
              This early snapshot has incomplete relationship history.
              Relationships not recorded in it will stay as they are now.
            </p>
          )}
          <p className={styles.note}>
            Shared People, Place, Collection, and track definitions stay
            current. Photo files are not deleted. Missing historical links or
            originals stop the restore safely.
          </p>
          <div className={styles.comparison}>
            <section aria-label="Earlier version">
              <h3>Version {selected.version}</h3>
              <Snapshot value={selected.snapshot} />
            </section>
            <section aria-label="Current version">
              <h3>Current · version {history.current.revision}</h3>
              <Snapshot value={history.current} />
            </section>
          </div>
        </>
      )}
      {!selected && (
        <>
          <p>No earlier versions on this page.</p>
          <div className={`${styles.comparison} ${styles.currentOnly}`}>
            <section aria-label="Current version">
              <h3>Current · version {history.current.revision}</h3>
              <Snapshot value={history.current} />
            </section>
          </div>
        </>
      )}
      <nav className={styles.pagination} aria-label="Version pages">
        {page > 1 && (
          <Link href={`/history?entry=${history.current.id}&page=${page - 1}`}>
            Newer versions
          </Link>
        )}
        <span>Page {page}</span>
        {history.total_count > page * 20 && (
          <Link href={`/history?entry=${history.current.id}&page=${page + 1}`}>
            Older versions
          </Link>
        )}
      </nav>
    </>
  );
}
function Snapshot({ value }: { value: HistorySnapshot }) {
  return (
    <>
      <h4>{historyTitle(value)}</h4>
      <p className={styles.body}>
        {value.body || "No writing in this version."}
      </p>
      <dl className={styles.facts}>
        <dt>Type</dt>
        <dd>{value.entry_type.replaceAll("_", " ")}</dd>
        <dt>Inbox</dt>
        <dd>{value.inbox_status}</dd>
        <dt>Date</dt>
        <dd>{historyDateLabel(value)}</dd>
        <dt>Time zone</dt>
        <dd>{value.occurred_timezone ?? "Unknown"}</dd>
      </dl>
      {[
        "collections",
        "tags",
        "people",
        "places",
        "timeline_items",
        "attachments",
      ].map((key) =>
        Array.isArray(value[key]) ? (
          <div key={key} className={styles.relationships}>
            <strong>{key.replaceAll("_", " ")}</strong>
            <p>
              {(value[key] as Record<string, unknown>[])
                .map((item) =>
                  String(
                    item.name ??
                      item.track_name ??
                      item.original_filename ??
                      item.id ??
                      item.person_id ??
                      item.place_id,
                  ),
                )
                .join(", ") || "None"}
            </p>
          </div>
        ) : null,
      )}
      {["home", "vehicle", "goal", "metadata", "links"].map((key) =>
        value[key] &&
        JSON.stringify(value[key]) !== "{}" &&
        JSON.stringify(value[key]) !== "[]" ? (
          <details key={key}>
            <summary>
              {key.charAt(0).toUpperCase() + key.slice(1)} details
            </summary>
            <pre className={styles.json}>
              {JSON.stringify(
                value[key],
                (name, item) =>
                  ["owner_id", "entry_id", "created_at", "updated_at"].includes(
                    name,
                  )
                    ? undefined
                    : item,
                2,
              )}
            </pre>
          </details>
        ) : null,
      )}
    </>
  );
}
