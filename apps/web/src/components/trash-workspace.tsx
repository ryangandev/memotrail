"use client";
import { Dialog } from "@/components/dialog";
import { EmptyState } from "@/components/empty-state";
import { PageHeader } from "@/components/page-header";
import { Button } from "@/components/button";

import Link from "next/link";
import { useState } from "react";
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
import { ProgressiveImage } from "@/components/progressive-image";
import type {
  TrashItem,
  TrashWorkspace as TrashWorkspaceData,
} from "@/lib/data/trash";
import { TRASH_PAGE_SIZE, trashPageHref } from "@/lib/data/trash-input";
import { wikiItemIdentityLabel } from "@/lib/data/wiki-item";

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
      <PageHeader
        title={<>Trash</>}
        eyebrow={<>Recoverable by design</>}
        description={
          <>
            Restore something you still need, or permanently remove it with an
            explicit confirmation.
          </>
        }
        actions={
          <>
            <div className={styles.retentionBadge}>
              <Icon name="clock" size={18} />
              <span>
                <strong>30-day retention</strong>
                <small>Dates are shown per item</small>
              </span>
            </div>
          </>
        }
      />

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
        <EmptyState
          title={<>Trash is unavailable</>}
          description={<>{workspace.loadError}</>}
          icon={
            <>
              <Icon name="refresh" size={25} />
            </>
          }
        />
      ) : workspace.items.length === 0 ? (
        <EmptyState
          title={<>Nothing in Trash</>}
          description={
            <>
              Removed Entries, Places, People, and individual photos will appear
              here. Legacy records remain recoverable too.
            </>
          }
          icon={
            <>
              <Icon name="trash" size={25} />
            </>
          }
        />
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
                      <ProgressiveImage
                        alt=""
                        sizes="(max-width: 720px) 88px, 124px"
                        src={item.imageUrl}
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
                    <Button
                      variant="secondary"

                      disabled={Boolean(pending) || batchBusy}
                      onClick={() => runAction(item, "restore")}
                      type="button"
                    >
                      {isPending && pending?.action === "restore"
                        ? "Restoring..."
                        : "Restore"}
                    </Button>
                    <Button
                      variant="danger"

                      disabled={Boolean(pending) || batchBusy}
                      onClick={() => {
                        setResult(null);
                        setConfirmation(item);
                      }}
                      type="button"
                    >
                      Delete forever
                    </Button>
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
        <Dialog
          open
          size="compact"
          title={<>Delete “{confirmation.title}” forever?</>}
          titleId="trash-confirmation-title"
          description={
            <>{deletionDescription(confirmation)} This cannot be undone.</>
          }
          eyebrow={<>Permanent action</>}
          busy={Boolean(pending)}
          onOpenChange={(open) => {
            if (!open) setConfirmation(null);
          }}
          footer={
            <>
              <Button
                variant="secondary"
                disabled={Boolean(pending)}
                onClick={() => setConfirmation(null)}
                type="button"
              >
                Cancel
              </Button>
              <Button
                variant="danger"
                autoFocus

                disabled={Boolean(pending)}
                onClick={() => runAction(confirmation, "delete")}
                type="button"
              >
                {pending?.action === "delete"
                  ? "Deleting..."
                  : "Delete forever"}
              </Button>
            </>
          }
        >
          {result?.status === "error" ? (
            <p className={styles.dialogError} aria-live="polite">
              {result.message}
            </p>
          ) : null}
        </Dialog>
      ) : null}
    </PageFrame>
  );
}

function iconForKind(kind: TrashItem["kind"]): "map" | "photo" | "timeline" {
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

  if (item.kind === "place") {
    return "Place";
  }

  return item.wikiItemKind && item.wikiItemSubtype
    ? wikiItemIdentityLabel(item.wikiItemKind, item.wikiItemSubtype)
    : "Entry";
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

  if (item.kind === "place") {
    return "The Place and its version history will be removed.";
  }

  return "The Entry, private photos, relationships, specialized details, and version history will be removed.";
}
