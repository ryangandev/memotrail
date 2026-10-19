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
import { EmptyTrashControl } from "@/components/empty-trash-control";
import { PageFrame } from "@/components/page-frame";
import { SeparatedList } from "@/components/separated-list";
import { ProgressiveImage } from "@/components/progressive-image";
import type {
  TrashItem,
  TrashWorkspace as TrashWorkspaceData,
} from "@/lib/data/trash";
import { TRASH_PAGE_SIZE, trashPageHref } from "@/lib/data/trash-input";
import { trashDate } from "@/lib/data/trash-dates";

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

  const showEmptyTrash = !workspace.loadError && workspace.totalCount > 0;

  return (
    <PageFrame width="list">
      <PageHeader
        title="Trash"
        meta="Removed Entries and photos stay restorable for 30 days."
        action={
          showEmptyTrash ? (
            <span className={styles.emptyTrash}>
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
            </span>
          ) : null
        }
      />

      {workspace.loadError ? (
        <EmptyState
          title="Trash is unavailable"
          description={workspace.loadError}
          icon={<Icon name="refresh" size={20} />}
        />
      ) : workspace.items.length === 0 ? (
        <EmptyState
          title="Nothing in Trash"
          description="Removed Entries and individual photos will appear here."
          icon={<Icon name="trash" size={20} />}
        />
      ) : (
        <>
          <div className={styles.list}>
            {workspace.items.map((item) => {
              const isPending = pending?.itemId === item.id;
              const expired =
                new Date(item.expiresAt).getTime() <=
                new Date(workspace.renderedAt).getTime();

              return (
                <article className={styles.row} key={`${item.kind}-${item.id}`}>
                  <div className={styles.body}>
                    <h2 className={styles.title}>
                      {item.wikiItemSubtype === "chapter" ? (
                        <span
                          aria-label="Chapter"
                          className={styles.kindIcon}
                          role="img"
                        >
                          <Icon name="timeline" size={16} />
                        </span>
                      ) : null}
                      <span className={styles.titleText}>{item.title}</span>
                    </h2>
                    {item.detail ? (
                      <p className={styles.detail}>{item.detail}</p>
                    ) : null}
                    <SeparatedList className={styles.facts}>
                      <time dateTime={item.deletedAt}>
                        Removed {trashDate(item.deletedAt, workspace.timezone)}
                      </time>
                      <time dateTime={item.expiresAt}>
                        {expired
                          ? "Eligible for cleanup since "
                          : "Restorable through "}
                        {trashDate(item.expiresAt, workspace.timezone)}
                      </time>
                    </SeparatedList>
                  </div>

                  {item.imageUrl ? (
                    <div className={styles.thumb}>
                      <ProgressiveImage
                        alt=""
                        sizes="48px"
                        src={item.imageUrl}
                      />
                    </div>
                  ) : null}

                  <div className={styles.actions}>
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
                <span />
              )}
              <span>
                Page {workspace.page} of {totalPages}
              </span>
              {workspace.page < totalPages ? (
                <Link href={trashPageHref(workspace.page + 1)}>Next</Link>
              ) : (
                <span />
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

function deletionDescription(item: TrashItem) {
  if (item.kind === "attachment") {
    return "The photo will be removed.";
  }

  return "The Entry and its photos will be removed.";
}
