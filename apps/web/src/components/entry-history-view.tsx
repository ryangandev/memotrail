"use client";
import { notify } from "@/components/app-toast";
import { PageHeader } from "@/components/page-header";
import { Button, ButtonLink } from "@/components/button";
import { useConfirmationDialog } from "@/components/confirmation-dialog";
import Link from "next/link";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { EntryReviewDialog } from "./entry-review-list";
import { EntryPhotoGallery } from "./entry-photo-gallery";
import { EntryRelationsPanel } from "./entry-relations";
import { EntryRichTextContent } from "./entry-rich-text-content";
import { Icon } from "./icon";
import { DatePickerField } from "./date-picker-field";
import { loadEditableEntry } from "@/app/history/actions";
import {
  restoreHistoryVersion,
  extractGoalFromItem,
  trashWikiItem,
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
import { entryRichTextMetadataKey } from "@/lib/data/rich-text";
import { wikiItemIdentityLabel, wikiItemKindLabel } from "@/lib/data/wiki-item";
import styles from "@/components/entry-history-view.module.css";
export function EntryHistoryView({
  history,
  mode = "history",
  page,
  ownerId,
}: {
  history: EntryHistory;
  mode?: "detail" | "history";
  page: number;
  ownerId: string;
}) {
  const router = useRouter();
  const requestConfirmation = useConfirmationDialog();
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
      setError("This item cannot be edited right now. Refresh and try again.");
    } finally {
      setBusy(false);
    }
  }
  const selected =
    history.versions.find((v) => v.version === version) ?? history.versions[0];
  async function restore() {
    if (!selected) return;
    const confirmed = await requestConfirmation({
      title: <>Restore version {selected.version}?</>,
      description: (
        <>
          Your current version will remain in history. Recorded links and photo
          membership will also be restored, while shared Collection and tag
          definitions stay current.
        </>
      ),
      confirmLabel: "Restore version",
      eyebrow: <>History action</>,
    });
    if (!confirmed) return;
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
        notify.success("Version restored.");
      }
    } catch {
      setError(
        "Could not confirm restoration. Refresh to check the latest version before trying again.",
      );
    } finally {
      setBusy(false);
    }
  }
  async function moveToTrash() {
    if (busy) return;
    const confirmed = await requestConfirmation({
      title: <>Move “{historyTitle(history.current)}” to Trash?</>,
      description: <>You can restore it later from Trash.</>,
      confirmLabel: "Move to Trash",
      eyebrow: <>Recoverable action</>,
      variant: "danger",
    });
    if (!confirmed) return;

    setBusy(true);
    setError(null);
    try {
      const message = await trashWikiItem(
        history.current.id,
        history.current.revision,
      );
      if (message) setError(message);
      else {
        router.push("/library");
        router.refresh();
        notify.info("Entry moved to Trash.");
      }
    } catch {
      setError(
        "Could not confirm the move to Trash. Refresh before trying again.",
      );
    } finally {
      setBusy(false);
    }
  }
  const detailMode = mode === "detail";
  return (
    <>
      <Link
        className={styles.backLink}
        href={detailMode ? "/library" : "/history"}
      >
        ← {detailMode ? "Library" : "All version history"}
      </Link>
      {detailMode ? (
        <PageHeader title={<>{historyTitle(history.current)}</>} />
      ) : (
        <h2>{historyTitle(history.current)}</h2>
      )}
      <div className={styles.itemActions}>
        {!history.current.deleted_at &&
          history.current.item_kind === "entry" &&
          ["entry", "source_capture"].includes(
            String(history.current.item_subtype),
          ) && (
            <Button
              variant="secondary"
              type="submit"
              disabled={busy}
              onClick={() => void edit()}
            >
              Edit {wikiItemKindLabel(history.current.item_kind)}
            </Button>
          )}
        {!history.current.deleted_at &&
          history.current.item_kind === "entry" &&
          history.current.item_subtype === "first_time" && (
            <ButtonLink href={`/first-times?entry=${history.current.id}`}>
              Edit First Time
            </ButtonLink>
          )}
        {!history.current.deleted_at &&
          history.current.item_kind === "entry" &&
          ["moment", "period"].includes(history.current.item_subtype) && (
            <ButtonLink href={`/timeline?entry=${history.current.id}`}>
              Edit{" "}
              {history.current.item_subtype === "period" ? "Period" : "Moment"}
            </ButtonLink>
          )}
        {detailMode && history.versions.length > 0 ? (
          <ButtonLink href={`/history?entry=${history.current.id}`}>
            View version history ({history.total_count})
          </ButtonLink>
        ) : null}
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
          <ButtonLink href={`/explore?entry=${history.current.id}`}>
            Explore with AI
          </ButtonLink>
        )}
        {!history.current.deleted_at &&
          history.current.item_kind !== "goal" && (
            <GoalExtraction
              key={`${history.current.id}:${history.current.revision}`}
              entry={history.current}
              disabled={busy}
              onBusyChange={setBusy}
            />
          )}
        {!history.current.deleted_at &&
          history.current.item_kind === "goal" && (
            <ButtonLink href={`/goals?entry=${history.current.id}`}>
              Open Goal
            </ButtonLink>
          )}
        {detailMode && !history.current.deleted_at ? (
          <Button
            variant="danger"
            className={styles.trashAction}
            disabled={busy}
            onClick={() => void moveToTrash()}
            type="button"
          >
            <Icon name="trash" size={16} />
            Move to Trash
          </Button>
        ) : null}
      </div>
      {error && <p role="alert">{error}</p>}
      {Array.isArray(history.current.links) &&
        history.current.links.map(
          (link: { target_entry_id?: unknown; relationship?: unknown }, i) =>
            typeof link.target_entry_id === "string" &&
            /^[0-9a-f-]{36}$/i.test(link.target_entry_id) &&
            [
              "derived",
              "derived_from",
              "exploration_source",
              "exploration_conclusion",
            ].includes(String(link.relationship)) ? (
              <p key={i}>
                <Link href={`/items/${link.target_entry_id}`}>
                  {link.relationship === "derived"
                    ? "Open extracted item"
                    : link.relationship === "derived_from" ||
                        link.relationship === "exploration_source"
                      ? "Open source item"
                      : "Open saved conclusion"}
                </Link>
              </p>
            ) : null,
        )}
      {!detailMode && history.versions.length > 0 && (
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
          <Button
            variant="secondary"
            type="submit"
            disabled={busy || !selected || Boolean(history.current.deleted_at)}
            onClick={restore}
          >
            {busy ? "Restoring…" : "Restore selected version"}
          </Button>
        </div>
      )}
      {history.current.deleted_at && (
        <p role="status">
          This item is in Trash. Restore it there before changing its history.
        </p>
      )}
      {detailMode ? (
        <CurrentItem value={history.current} />
      ) : selected ? (
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
            People, Collection, and track definitions stay current. Historical
            Location links return to their original snapshots. Photo files are
            not deleted. Missing historical links or originals stop the restore
            safely.
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
      ) : (
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
      {!detailMode ? (
        <nav className={styles.pagination} aria-label="Version pages">
          {page > 1 && (
            <Link
              href={`/history?entry=${history.current.id}&page=${page - 1}`}
            >
              Newer versions
            </Link>
          )}
          <span>Page {page}</span>
          {history.total_count > page * 20 && (
            <Link
              href={`/history?entry=${history.current.id}&page=${page + 1}`}
            >
              Older versions
            </Link>
          )}
        </nav>
      ) : null}
    </>
  );
}

function CurrentItem({ value }: { value: HistorySnapshot }) {
  const groups = [
    "collections",
    "tags",
    "people",
    "places",
    "timeline_items",
  ].flatMap((key) => {
    const items = value[key];
    if (!Array.isArray(items) || items.length === 0) return [];
    return [
      {
        key,
        label: key.replaceAll("_", " "),
        value: (items as Record<string, unknown>[])
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
          .join(", "),
      },
    ];
  });

  return (
    <article className={styles.currentItem} aria-label="Current item">
      <EntryRichTextContent
        body={value.body || "No writing has been added yet."}
        className={styles.currentBody}
        metadata={value.body ? value.metadata : undefined}
      />
      <dl className={styles.currentFacts}>
        {value.item_kind !== "entry" ||
        !["entry", "source_capture"].includes(value.item_subtype) ? (
          <div>
            <dt>Record</dt>
            <dd>
              {wikiItemIdentityLabel(value.item_kind, value.item_subtype)}
            </dd>
          </div>
        ) : null}
        <div>
          <dt>Date</dt>
          <dd>{historyDateLabel(value)}</dd>
        </div>
        {groups.map((group) => (
          <div key={group.key}>
            <dt>{group.label}</dt>
            <dd>{group.value}</dd>
          </div>
        ))}
      </dl>
    </article>
  );
}
function GoalExtraction({
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
  const [goalId, setGoalId] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [title, setTitle] = useState(entry.title ?? "");
  const [horizon, setHorizon] = useState<GoalHorizon>("someday");
  const [status, setStatus] = useState<GoalStatus>("considering");
  const [targetDate, setTargetDate] = useState("");
  const [error, setError] = useState<string | null>(null);
  if (!open)
    return (
      <Button
        variant="primary"
        type="submit"
        disabled={disabled}
        onClick={() => {
          setGoalId(crypto.randomUUID());
          setOpen(true);
        }}
      >
        Create linked Goal
      </Button>
    );
  return (
    <form
      aria-label="Create linked Goal"
      className={styles.conversion}
      onSubmit={async (event) => {
        event.preventDefault();
        setBusy(true);
        onBusyChange(true);
        setError(null);
        try {
          if (!goalId) throw Error("Missing Goal identity");
          const result = await extractGoalFromItem({
            goalId,
            sourceId: entry.id,
            sourceRevision: entry.revision,
            title,
            horizon,
            status,
            targetDate: targetDate || null,
          });
          if (result.error) setError(result.error);
          else if (result.goalId) {
            setOpen(false);
            router.push(`/goals?entry=${result.goalId}`);
          }
        } catch {
          setError(
            "Could not confirm Goal creation. Refresh to check the source before retrying.",
          );
        } finally {
          setBusy(false);
          onBusyChange(false);
        }
      }}
    >
      <h3>Create a Goal from this item</h3>
      <p>
        This creates a separate Goal and links it back to this source. The
        source keeps its writing, dates, photos, links, and history.
      </p>
      <fieldset disabled={busy || disabled}>
        <label>
          Goal title <span aria-hidden="true">*</span>
          <input
            aria-label="Goal title"
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
        <DatePickerField
          disabled={busy}
          label="Target date"
          value={targetDate}
          onChange={setTargetDate}
        />
        <div className={styles.controls}>
          <Button
            variant="secondary"
            type="button"
            onClick={() => {
              setOpen(false);
              setGoalId(null);
            }}
          >
            Cancel
          </Button>
          <Button variant="primary" type="submit">
            {busy ? "Creating..." : "Create linked Goal"}
          </Button>
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
      <EntryRichTextContent
        body={value.body || "No writing in this version."}
        className={styles.body}
        metadata={value.body ? value.metadata : undefined}
      />
      <dl className={styles.facts}>
        <dt>Type</dt>
        <dd>{wikiItemIdentityLabel(value.item_kind, value.item_subtype)}</dd>
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
      {["home", "vehicle", "goal", "metadata", "links"].map((key) => {
        const detail = snapshotDetail(value, key);
        return detail &&
          JSON.stringify(detail) !== "{}" &&
          JSON.stringify(detail) !== "[]" ? (
          <details key={key}>
            <summary>
              {key.charAt(0).toUpperCase() + key.slice(1)} details
            </summary>
            <pre className={styles.json}>
              {JSON.stringify(
                detail,
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
        ) : null;
      })}
    </>
  );
}

function snapshotDetail(value: HistorySnapshot, key: string) {
  const detail = value[key];
  if (key !== "metadata" || !isRecord(detail)) return detail;

  const visibleMetadata = { ...detail };
  delete visibleMetadata[entryRichTextMetadataKey];
  return visibleMetadata;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
