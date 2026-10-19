"use client";
import { Dialog } from "@/components/dialog";
import { EmptyState } from "@/components/empty-state";
import { PageHeader } from "@/components/page-header";
import { Button } from "@/components/button";
import { notify } from "@/components/app-toast";

import Link from "next/link";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import {
  deleteTrashItemForever,
  finishTrashCleanup,
  restoreTrashItem,
  type TrashActionResult,
} from "@/app/trash/actions";
import styles from "@/components/trash-workspace.module.css";
import { Icon } from "@/components/icon";
import { Badge } from "@/components/badge";
import { EmptyTrashControl } from "@/components/empty-trash-control";
import { PageFrame } from "@/components/page-frame";
import { ProgressiveImage } from "@/components/progressive-image";
import type {
  TrashItem,
  TrashWorkspace as TrashWorkspaceData,
} from "@/lib/data/trash";
import { TRASH_PAGE_SIZE, trashPageHref } from "@/lib/data/trash-input";
import { trashDate, trashRetention } from "@/lib/data/trash-dates";
import { wikiItemSubtypeLabel } from "@/lib/data/wiki-item";

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
  const [batchBusy, setBatchBusy] = useState(false);
  const firstItemNumber = (workspace.page - 1) * TRASH_PAGE_SIZE + 1;
  const lastItemNumber = Math.min(
    workspace.page * TRASH_PAGE_SIZE,
    workspace.totalCount,
  );
  const totalPages = Math.ceil(workspace.totalCount / TRASH_PAGE_SIZE);

  useEffect(() => {
    // Finish removing the files of anything already deleted forever, including a
    // removal that another device or an interrupted request left unfinished.
    void finishTrashCleanup().catch(() => undefined);
  }, []);

  async function runAction(item: TrashItem, action: "delete" | "restore") {
    setPending({ action, itemId: item.id });

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
      announceResult(nextResult);

      if (nextResult.status !== "error") {
        setConfirmation(null);

        if (workspace.items.length === 1 && workspace.page > 1) {
          router.push(trashPageHref(workspace.page - 1));
        } else {
          router.refresh();
        }
      }
    } catch {
      notify.error(
        "MemoTrail could not reach the server. Try again when online.",
      );
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

      {!workspace.loadError && workspace.totalCount > 0 ? (
        <div className={styles.actionRow}>
          <EmptyTrashControl
            disabled={Boolean(pending) || Boolean(confirmation)}
            reviewsExist={workspace.reviewsExist}
            onBusy={setBatchBusy}
            onResult={announceResult}
            onFinish={() => {
              if (workspace.page > 1) router.push("/trash");
              else router.refresh();
            }}
          />
        </div>
      ) : null}

      {workspace.loadError ? (
        <div className={styles.emptyState}>
          <EmptyState
            title={<>Trash is unavailable</>}
            description={<>{workspace.loadError}</>}
            icon={
              <>
                <Icon name="refresh" size={25} />
              </>
            }
          />
        </div>
      ) : workspace.items.length === 0 ? (
        <div className={styles.emptyState}>
          <EmptyState
            title={<>Nothing in Trash</>}
            description={
              <>
                Removed Entries and individual photos will appear here. Legacy
                records remain recoverable too.
              </>
            }
            icon={
              <>
                <Icon name="trash" size={25} />
              </>
            }
          />
        </div>
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
                      <Badge tone="warm">{labelForItem(item)}</Badge>
                      <time dateTime={item.deletedAt}>
                        Removed {trashDate(item.deletedAt, workspace.timezone)}
                      </time>
                    </div>
                    <h2>{item.title}</h2>
                    {item.detail ? <p>{item.detail}</p> : null}
                    <div className={styles.retentionLine}>
                      <Icon name="clock" size={14} />
                      <span>
                        {trashRetention(item.expiresAt, workspace.renderedAt)}
                      </span>
                      <time dateTime={item.expiresAt}>
                        {trashDate(item.expiresAt, workspace.timezone)}
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
            <>
              {deletionDescription(confirmation)}
              {workspace.reviewsExist && confirmation.kind !== "attachment"
                ? " Reviews that read these Entries are deleted too."
                : ""}{" "}
              This cannot be undone.
            </>
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
                data-autofocus
                disabled={Boolean(pending)}
                onClick={() => setConfirmation(null)}
                type="button"
              >
                Cancel
              </Button>
              <Button
                variant="danger"
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
        />
      ) : null}
    </PageFrame>
  );
}

function announceResult(result: TrashActionResult) {
  if (result.status === "error") notify.error(result.message);
  else notify.success(result.message);
}

function iconForKind(kind: TrashItem["kind"]): "photo" | "timeline" {
  return kind === "attachment" ? "photo" : "timeline";
}

function labelForItem(item: TrashItem) {
  if (item.kind === "attachment") {
    return "Photo";
  }

  return item.wikiItemSubtype
    ? wikiItemSubtypeLabel(item.wikiItemSubtype)
    : "Entry";
}

function deletionDescription(item: TrashItem) {
  if (item.kind === "attachment") {
    return "The private photo file and its attachment record will be removed.";
  }

  return "The Entry, private photos, relationships, and specialized details will be removed.";
}
