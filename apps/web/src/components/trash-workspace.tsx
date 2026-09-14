"use client";

import Image from "next/image";
import Link from "next/link";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import {
  deleteTrashItemForever,
  restoreTrashItem,
  type TrashActionResult,
} from "@/app/trash/actions";
import styles from "@/app/trash/page.module.css";
import { Icon } from "@/components/icon";
import { EmptyTrashControl } from "@/components/empty-trash-control";
import { PageFrame } from "@/components/page-frame";
import type {
  TrashItem,
  TrashWorkspace as TrashWorkspaceData,
} from "@/lib/data/trash";
import { TRASH_PAGE_SIZE, trashPageHref } from "@/lib/data/trash-input";

type PendingAction = {
  action: "delete" | "restore";
  itemId: string;
};

export function TrashWorkspace({
  workspace,
}: {
  workspace: TrashWorkspaceData;
}) {
  const router = useRouter();
  const [confirmation, setConfirmation] = useState<TrashItem | null>(null);
  const [pending, setPending] = useState<PendingAction | null>(null);
  const [result, setResult] = useState<TrashActionResult | null>(null);
  const [batchBusy, setBatchBusy] = useState(false);
  const firstItemNumber = (workspace.page - 1) * TRASH_PAGE_SIZE + 1;
  const lastItemNumber = Math.min(
    workspace.page * TRASH_PAGE_SIZE,
    workspace.totalCount,
  );
  const totalPages = Math.ceil(workspace.totalCount / TRASH_PAGE_SIZE);

  useEffect(() => {
    if (!confirmation) {
      return;
    }

    function closeOnEscape(event: KeyboardEvent) {
      if (event.key === "Escape" && !pending) {
        setConfirmation(null);
      }
    }

    document.addEventListener("keydown", closeOnEscape);
    return () => document.removeEventListener("keydown", closeOnEscape);
  }, [confirmation, pending]);

  async function runAction(item: TrashItem, action: "delete" | "restore") {
    setPending({ action, itemId: item.id });
    setResult(null);

    try {
      const input = {
        deletedAt: item.deletedAt,
        itemId: item.id,
        itemKind: item.kind,
        revision: item.revision,
      };
      const nextResult =
        action === "restore"
          ? await restoreTrashItem(input)
          : await deleteTrashItemForever(input);
      setResult(nextResult);

      if (nextResult.status !== "error") {
        setConfirmation(null);

        if (workspace.items.length === 1 && workspace.page > 1) {
          router.push(trashPageHref(workspace.page - 1));
        } else {
          router.refresh();
        }
      }
    } catch {
      setResult({
        message: "MemoTrail could not reach the server. Try again when online.",
        status: "error",
      });
    } finally {
      setPending(null);
    }
  }

  return (
    <PageFrame variant="standard">
      <header className={styles.pageHeader}>
        <div>
          <p className={styles.eyebrow}>Recoverable by design</p>
          <h1>Trash</h1>
          <p>
            Restore something you still need, or permanently remove it with an
            explicit confirmation.
          </p>
        </div>
        <div className={styles.retentionBadge}>
          <Icon name="clock" size={18} />
          <span>
            <strong>30-day retention</strong>
            <small>Dates are shown per item</small>
          </span>
        </div>
      </header>

      <aside className={styles.retentionNote}>
        <Icon name="archive" size={19} />
        <p>
          Items remain recoverable during their retention window. Reaching the
          shown date makes an item eligible for cleanup, but this screen does
          not claim it was automatically deleted.
        </p>
      </aside>

      <EmptyTrashControl
        disabled={
          Boolean(pending) ||
          Boolean(confirmation) ||
          Boolean(workspace.loadError) ||
          workspace.totalCount === 0
        }
        onBusy={setBatchBusy}
        onResult={setResult}
        onFinish={() => {
          if (workspace.page > 1) router.push("/trash");
          else router.refresh();
        }}
      />

      {result ? (
        <p
          aria-live="polite"
          className={
            result.status === "error"
              ? styles.errorMessage
              : styles.successMessage
          }
        >
          {result.message}
        </p>
      ) : null}

      {workspace.loadError ? (
        <section className={styles.emptyState}>
          <Icon name="refresh" size={25} />
          <h2>Trash is unavailable</h2>
          <p>{workspace.loadError}</p>
        </section>
      ) : workspace.items.length === 0 ? (
        <section className={styles.emptyState}>
          <Icon name="trash" size={25} />
          <h2>Nothing in Trash</h2>
          <p>
            Removed Entries, Places, People, and individual photos will appear
            here. Legacy records remain recoverable too.
          </p>
        </section>
      ) : (
        <>
          <div className={styles.listSummary}>
            <span>
              {firstItemNumber}-{lastItemNumber} of {workspace.totalCount}
            </span>
            <small>Newest removals first</small>
          </div>
          <div className={styles.trashList}>
            {workspace.items.map((item) => {
              const isPending = pending?.itemId === item.id;

              return (
                <article
                  className={styles.trashCard}
                  key={`${item.kind}-${item.id}`}
                >
                  {item.imageUrl ? (
                    <div className={styles.itemImage}>
                      <Image
                        alt=""
                        fill
                        sizes="(max-width: 720px) 88px, 124px"
                        src={item.imageUrl}
                        unoptimized
                      />
                    </div>
                  ) : (
                    <div className={styles.itemGlyph}>
                      <Icon name={iconForKind(item.kind)} size={23} />
                    </div>
                  )}

                  <div className={styles.itemBody}>
                    <div className={styles.itemMeta}>
                      <span>{labelForItem(item)}</span>
                      <time dateTime={item.deletedAt}>
                        Removed {formatDate(item.deletedAt)}
                      </time>
                    </div>
                    <h2>{item.title}</h2>
                    {item.detail && item.detail !== item.title ? (
                      <p>{item.detail}</p>
                    ) : null}
                    <div className={styles.retentionLine}>
                      <Icon name="clock" size={14} />
                      <span>{retentionLabel(item.expiresAt)}</span>
                      <time dateTime={item.expiresAt}>
                        {formatDate(item.expiresAt)}
                      </time>
                    </div>
                  </div>

                  <div className={styles.itemActions}>
                    <button
                      className={styles.restoreButton}
                      disabled={Boolean(pending) || batchBusy}
                      onClick={() => runAction(item, "restore")}
                      type="button"
                    >
                      {isPending && pending?.action === "restore"
                        ? "Restoring..."
                        : "Restore"}
                    </button>
                    <button
                      className={styles.deleteButton}
                      disabled={Boolean(pending) || batchBusy}
                      onClick={() => {
                        setResult(null);
                        setConfirmation(item);
                      }}
                      type="button"
                    >
                      Delete forever
                    </button>
                  </div>
                </article>
              );
            })}
          </div>

          {totalPages > 1 ? (
            <nav className={styles.pagination} aria-label="Trash pages">
              {workspace.page > 1 ? (
                <Link href={trashPageHref(workspace.page - 1)}>Previous</Link>
              ) : (
                <span>Previous</span>
              )}
              <small>
                Page {workspace.page} of {totalPages}
              </small>
              {workspace.page < totalPages ? (
                <Link href={trashPageHref(workspace.page + 1)}>Next</Link>
              ) : (
                <span>Next</span>
              )}
            </nav>
          ) : null}
        </>
      )}

      {confirmation ? (
        <div
          className={styles.dialogBackdrop}
          onMouseDown={(event) => {
            if (event.currentTarget === event.target && !pending) {
              setConfirmation(null);
            }
          }}
        >
          <section
            aria-describedby="trash-confirmation-description"
            aria-labelledby="trash-confirmation-title"
            aria-modal="true"
            className={styles.confirmationDialog}
            role="dialog"
          >
            <div className={styles.dialogIcon}>
              <Icon name="trash" size={22} />
            </div>
            <p className={styles.dialogEyebrow}>Permanent action</p>
            <h2 id="trash-confirmation-title">
              Delete “{confirmation.title}” forever?
            </h2>
            <p id="trash-confirmation-description">
              {deletionDescription(confirmation)} This cannot be undone.
            </p>
            {result?.status === "error" ? (
              <p className={styles.dialogError} aria-live="polite">
                {result.message}
              </p>
            ) : null}
            <div className={styles.dialogActions}>
              <button
                disabled={Boolean(pending)}
                onClick={() => setConfirmation(null)}
                type="button"
              >
                Cancel
              </button>
              <button
                autoFocus
                className={styles.confirmDeleteButton}
                disabled={Boolean(pending)}
                onClick={() => runAction(confirmation, "delete")}
                type="button"
              >
                {pending?.action === "delete"
                  ? "Deleting..."
                  : "Delete forever"}
              </button>
            </div>
          </section>
        </div>
      ) : null}
    </PageFrame>
  );
}

function iconForKind(
  kind: TrashItem["kind"],
): "check" | "map" | "photo" | "timeline" {
  if (kind === "habit") {
    return "check";
  }

  if (kind === "place") {
    return "map";
  }

  return kind === "attachment" ? "photo" : "timeline";
}

function labelForItem(item: TrashItem) {
  if (item.kind === "collection") return "Collection";
  if (item.kind === "person") return "Person";
  if (item.kind === "attachment") {
    return "Photo";
  }

  if (item.kind === "habit") {
    return "Habit";
  }

  if (item.kind === "place") {
    return "Place";
  }

  return item.entryType === "first_time" ? "First Time" : "Entry";
}

function formatDate(value: string) {
  return new Intl.DateTimeFormat(undefined, {
    day: "numeric",
    month: "short",
    year: "numeric",
  }).format(new Date(value));
}

function retentionLabel(value: string) {
  const days = Math.ceil((new Date(value).getTime() - Date.now()) / 86_400_000);

  if (days <= 0) {
    return "Eligible for cleanup since";
  }

  return `${days} ${days === 1 ? "day" : "days"} to restore · through`;
}

function deletionDescription(item: TrashItem) {
  if (item.kind === "collection")
    return "Only the Collection and its grouping links will be removed. Your Entries and photos stay in the archive.";
  if (item.kind === "person")
    return "The Person and their version history will be removed.";
  if (item.kind === "attachment") {
    return "The private photo file and its attachment record will be removed.";
  }

  if (item.kind === "habit") {
    return "The Habit, check-ins, relationships, and version history will be removed.";
  }

  if (item.kind === "place") {
    return "The Place and its version history will be removed.";
  }

  return "The Entry, private photos, relationships, specialized details, and version history will be removed.";
}
