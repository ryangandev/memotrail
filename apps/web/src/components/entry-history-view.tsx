"use client";
import Link from "next/link";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { EntryReviewDialog } from "./entry-review-list";
import { EntryPhotoGallery } from "./entry-photo-gallery";
import { EntryRelationsPanel } from "./entry-relations";
import { loadEditableEntry } from "@/app/history/actions";
import {
  restoreHistoryVersion,
  convertEntryToGoal,
} from "@/app/history/actions";
import {
  goalHorizons,
  goalStatuses,
  type GoalHorizon,
  type GoalStatus,
} from "@/lib/data/goal-record-input";
import { goalHorizonLabels, goalStatusLabels } from "@/lib/data/goal-record";
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
  ownerId,
}: {
  history: EntryHistory;
  page: number;
  ownerId: string;
}) {
  const router = useRouter();
  const [version, setVersion] = useState<number | undefined>(
    history.versions[0]?.version,
  );
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [editing, setEditing] =
    useState<Awaited<ReturnType<typeof loadEditableEntry>>>(null);
  async function edit() {
    setBusy(true);
    setError(null);
    try {
      const data = await loadEditableEntry(history.current.id);
      if (!data) throw Error();
      setEditing(data);
    } catch {
      setError("This Entry cannot be edited right now. Refresh and try again.");
    } finally {
      setBusy(false);
    }
  }
  const selected =
    history.versions.find((v) => v.version === version) ?? history.versions[0];
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
      else {
        setVersion(undefined);
        router.refresh();
      }
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
      {!history.current.deleted_at &&
        ["standard", "first_time"].includes(history.current.entry_type) && (
          <button disabled={busy} onClick={() => void edit()}>
            Edit Entry
          </button>
        )}
      {editing && (
        <EntryReviewDialog
          entry={editing.entry}
          organized={editing.organized}
          collectionOptions={editing.entry.collectionNames}
          tagOptions={editing.entry.tagNames}
          onClose={() => setEditing(null)}
          onSaved={() => {
            setEditing(null);
            router.refresh();
          }}
        />
      )}
      {!history.current.deleted_at && (
        <Link href={`/explore?entry=${history.current.id}`}>
          Explore with AI
        </Link>
      )}
      {!history.current.deleted_at &&
        history.current.entry_type === "standard" && (
          <GoalConversion
            key={`${history.current.id}:${history.current.revision}`}
            entry={history.current}
            disabled={busy}
            onBusyChange={setBusy}
          />
        )}
      {!history.current.deleted_at && history.current.entry_type === "goal" && (
        <Link href={`/goals?entry=${history.current.id}`}>Open Goal</Link>
      )}
      {Array.isArray(history.current.links) &&
        history.current.links.map(
          (link: { target_entry_id?: unknown; relationship?: unknown }, i) =>
            typeof link.target_entry_id === "string" &&
            /^[0-9a-f-]{36}$/i.test(link.target_entry_id) &&
            ["exploration_source", "exploration_conclusion"].includes(
              String(link.relationship),
            ) ? (
              <p key={i}>
                <Link href={`/history?entry=${link.target_entry_id}`}>
                  {link.relationship === "exploration_source"
                    ? "Open source Entry"
                    : "Open saved conclusion"}
                </Link>
              </p>
            ) : null,
        )}
      {history.versions.length > 0 && (
        <div className={styles.controls}>
          <label>
            Earlier version
            <select
              value={selected?.version ?? ""}
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
      {!history.current.deleted_at && (
        <EntryRelationsPanel
          key={`relations:${history.current.id}:${history.current.revision}`}
          entryID={history.current.id}
        />
      )}
      {!history.current.deleted_at && (
        <EntryPhotoGallery
          key={`photos:${history.current.id}`}
          entryId={history.current.id}
          entryRevision={history.current.revision}
          ownerId={ownerId}
          onChanged={() => router.refresh()}
        />
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
function GoalConversion({
  entry,
  disabled,
  onBusyChange,
}: {
  entry: HistorySnapshot;
  disabled: boolean;
  onBusyChange: (busy: boolean) => void;
}) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [title, setTitle] = useState(entry.title ?? "");
  const [horizon, setHorizon] = useState<GoalHorizon>("someday");
  const [status, setStatus] = useState<GoalStatus>("considering");
  const [targetDate, setTargetDate] = useState("");
  const [error, setError] = useState<string | null>(null);
  if (!open)
    return (
      <button disabled={disabled} onClick={() => setOpen(true)}>
        Convert to Goal
      </button>
    );
  return (
    <form
      aria-label="Convert Entry to Goal"
      className={styles.conversion}
      onSubmit={async (event) => {
        event.preventDefault();
        setBusy(true);
        onBusyChange(true);
        setError(null);
        try {
          const message = await convertEntryToGoal({
            id: entry.id,
            revision: entry.revision,
            title,
            horizon,
            status,
            targetDate: targetDate || null,
          });
          if (message) setError(message);
          else {
            setOpen(false);
            router.refresh();
          }
        } catch {
          setError(
            "Could not confirm conversion. Refresh to check the current Entry before retrying.",
          );
        } finally {
          setBusy(false);
          onBusyChange(false);
        }
      }}
    >
      <h3>Give this idea an intention</h3>
      <p>
        This keeps the same Entry, original writing, dates, photos, links, and
        Inbox state. No copy or Bucket List membership is created. You can
        restore the Standard version through history.
      </p>
      <fieldset disabled={busy || disabled}>
        <label>
          Goal title
          <input
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            maxLength={200}
            required
          />
        </label>
        <label>
          Horizon
          <select
            value={horizon}
            onChange={(e) => setHorizon(e.target.value as GoalHorizon)}
          >
            {goalHorizons.map((v) => (
              <option key={v} value={v}>
                {goalHorizonLabels[v]}
              </option>
            ))}
          </select>
        </label>
        <label>
          Status
          <select
            value={status}
            onChange={(e) => setStatus(e.target.value as GoalStatus)}
          >
            {goalStatuses.map((v) => (
              <option key={v} value={v}>
                {goalStatusLabels[v]}
              </option>
            ))}
          </select>
        </label>
        <label>
          Target date (optional)
          <input
            type="date"
            value={targetDate}
            onChange={(e) => setTargetDate(e.target.value)}
          />
        </label>
        <div className={styles.controls}>
          <button type="button" onClick={() => setOpen(false)}>
            Cancel
          </button>
          <button type="submit">
            {busy ? "Converting..." : "Convert this Entry"}
          </button>
        </div>
      </fieldset>
      {error && <p role="alert">{error}</p>}
    </form>
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
