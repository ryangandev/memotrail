"use client";
import { notify } from "@/components/app-toast";
import { Dialog } from "@/components/dialog";
import { useConfirmationDialog } from "@/components/confirmation-dialog";
import { Button, IconButton } from "@/components/button";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState, type FormEvent, type ReactNode } from "react";
import {
  deleteUnusedTag,
  loadTagEntryPreviews,
  mergeTags,
  saveTag,
} from "@/app/organization/actions";
import { Icon } from "@/components/icon";
import { SelectField } from "@/components/select-field";
import { Skeleton } from "@/components/skeleton";
import { TextField } from "@/components/text-field";
import {
  tagNameLengthLimit,
  validTagInput,
  type TagEntryPreviewResult,
  type TagItem,
} from "@/lib/data/organization";
import styles from "./tag-control.module.css";
import { countLabel } from "@/lib/count-label";

export function TagControl({
  item,
  items = [],
  trigger,
  triggerClassName,
}: {
  item?: TagItem;
  items?: TagItem[];
  trigger?: ReactNode;
  triggerClassName?: string;
}) {
  const requestConfirmation = useConfirmationDialog();
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [name, setName] = useState(item?.name ?? "");
  const [targetId, setTargetId] = useState("");
  const [tagPreview, setTagPreview] = useState<TagEntryPreviewResult | null>(
    null,
  );
  const mergeTargets = items.filter((candidate) => candidate.id !== item?.id);
  const input = {
    id: item?.id ?? null,
    name,
    revision: item?.revision ?? null,
  } as const;

  useEffect(() => {
    if (!open || !item) return;
    let active = true;

    if (item.entry_count === 0) {
      return;
    }

    void loadTagEntryPreviews(item.name).then((preview) => {
      if (active) setTagPreview(preview);
    });

    return () => {
      active = false;
    };
  }, [item, open]);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (busy || !validTagInput(input)) return;
    await run(() => saveTag(input), `Tag ${item ? "saved" : "created"}.`);
  }

  async function remove() {
    if (!item || busy) return;
    const confirmed = await requestConfirmation({
      title: <>Delete the unused tag “{item.name}”?</>,
      description: <>This tag is unused and will be removed permanently.</>,
      confirmLabel: "Delete tag",
      variant: "danger",
    });
    if (!confirmed) return;
    await run(
      () => deleteUnusedTag({ id: item.id, revision: item.revision }),
      "Tag deleted.",
    );
  }

  async function merge() {
    const target = mergeTargets.find((candidate) => candidate.id === targetId);
    if (!item || !target || busy) return;
    const confirmed = await requestConfirmation({
      title: (
        <>
          Merge “{item.name}” into “{target.name}”?
        </>
      ),
      description: (
        <>
          Every Entry will use “{target.name}” and “{item.name}” will be
          removed.
        </>
      ),
      confirmLabel: "Merge tags",
      variant: "danger",
    });
    if (!confirmed) return;
    await run(
      () =>
        mergeTags({
          source: { id: item.id, revision: item.revision },
          target: { id: target.id, revision: target.revision },
        }),
      "Tags merged.",
    );
  }

  async function run(action: () => Promise<string | null>, success: string) {
    setBusy(true);
    try {
      const error = await action();
      if (error) {
        notify.error(error);
        return;
      }
      setOpen(false);
      router.refresh();
      notify.success(success);
    } catch {
      notify.error("Could not connect. Your changes are still here to retry.");
    } finally {
      setBusy(false);
    }
  }

  function openEditor() {
    // An editor closed without saving never keeps its unsaved changes.
    setName(item?.name ?? "");
    setTargetId("");
    setTagPreview(null);
    setOpen(true);
  }

  return (
    <>
      {trigger ? (
        <button
          aria-label={
            trigger && item
              ? `Manage tag ${item.name}, used by ${countLabel(item.entry_count, "Entry")}`
              : item
                ? `Edit ${item.name}`
                : "New Tag"
          }
          className={triggerClassName}
          onClick={openEditor}
          type="button"
        >
          {trigger}
        </button>
      ) : item ? (
        <IconButton
          label={`Edit ${item.name}`}
          variant="quiet"
          onClick={openEditor}
        >
          <Icon name="more" size={17} />
        </IconButton>
      ) : (
        <Button onClick={openEditor}>
          <Icon name="plus" size={17} /> New Tag
        </Button>
      )}

      {open ? (
        <Dialog
          open
          onOpenChange={(nextOpen) => {
            if (!nextOpen) setOpen(false);
          }}
          title={<>{item?.name ?? "Create a Tag"}</>}
          titleId={`tag-control-${item?.id ?? "new"}`}
          headerContent={
            <>
              {item ? (
                <span className={styles.usageCount}>
                  Used by {countLabel(item.entry_count, "Entry")}
                </span>
              ) : null}
            </>
          }
          closeLabel="Close tag editor"
          busy={busy}
          size="standard"
          footer={
            <div className={styles.editorActions}>
              <div>
                {item && item.entry_count === 0 ? (
                  <Button
                    variant="danger"
                    disabled={busy}
                    onClick={() => void remove()}
                    type="button"
                  >
                    Delete unused tag
                  </Button>
                ) : null}
              </div>
              <div>
                <Button
                  variant="secondary"
                  disabled={busy}
                  onClick={() => setOpen(false)}
                  type="button"
                >
                  Cancel
                </Button>
                <Button
                  form="tag-control-form"
                  variant="primary"
                  disabled={busy || !validTagInput(input)}
                  type="submit"
                >
                  {busy ? "Saving..." : item ? "Save changes" : "Create Tag"}
                </Button>
              </div>
            </div>
          }
        >
          <div className={styles.editorContent}>
            <form id="tag-control-form" onSubmit={submit}>
              <fieldset disabled={busy}>
                <TextField
                  autoFocus
                  disabled={busy}
                  label="Name"
                  maxLength={tagNameLengthLimit}
                  onChange={(event) => setName(event.target.value)}
                  required
                  value={name}
                />
              </fieldset>
            </form>
            {item ? (
              <TagEntryList
                count={item.entry_count}
                name={item.name}
                preview={tagPreview}
              />
            ) : null}
            {item && item.entry_count > 0 ? (
              <div className={styles.mergePanel}>
                <div>
                  <strong>Merge this tag</strong>
                  <p>
                    This tag is used by {countLabel(item.entry_count, "Entry")}.
                    Merge it to preserve every assignment.
                  </p>
                </div>
                <SelectField
                  disabled={busy || mergeTargets.length === 0}
                  label="Destination tag"
                  onChange={(event) => setTargetId(event.target.value)}
                  value={targetId}
                >
                  <option value="">Choose a tag</option>
                  {mergeTargets.map((candidate) => (
                    <option key={candidate.id} value={candidate.id}>
                      #{candidate.name} ({candidate.entry_count})
                    </option>
                  ))}
                </SelectField>
                <Button
                  variant="secondary"
                  disabled={busy || !targetId}
                  onClick={() => void merge()}
                  type="button"
                >
                  Merge tag
                </Button>
              </div>
            ) : null}
          </div>
        </Dialog>
      ) : null}
    </>
  );
}

function TagEntryList({
  count,
  name,
  preview,
}: {
  count: number;
  name: string;
  preview: TagEntryPreviewResult | null;
}) {
  const allEntriesHref = `/library?tag=${encodeURIComponent(name)}`;

  return (
    <section
      aria-labelledby="tag-entry-list-heading"
      className={styles.entryPanel}
    >
      <header>
        <div>
          <strong id="tag-entry-list-heading">Entries using this tag</strong>
          <span>{countLabel(count, "Entry")}</span>
        </div>
        {count > 5 ? <span>Showing 5</span> : null}
      </header>

      {count === 0 ? (
        <p className={styles.emptyEntries}>No Entries use this tag yet.</p>
      ) : preview === null ? (
        <div
          aria-label="Loading tagged Entries"
          className={styles.entryLoading}
          role="status"
        >
          <Skeleton height="34px" shape="line" />
          <Skeleton height="34px" shape="line" width="86%" />
          <Skeleton height="34px" shape="line" width="72%" />
        </div>
      ) : preview.error ? (
        <p className={styles.entryError} role="alert">
          {preview.error}
        </p>
      ) : (
        <ul className={styles.entryList}>
          {preview.entries.map((entry) => (
            <li key={entry.id}>
              <Link href={entry.href}>
                <strong>{entry.title}</strong>
                <span>
                  {entry.date ? `${entry.type} · ${entry.date}` : entry.type}
                </span>
              </Link>
            </li>
          ))}
        </ul>
      )}

      {count > 0 ? (
        <Link className={styles.viewAllEntries} href={allEntriesHref}>
          <span>View all Entries for this tag</span>
          <Icon name="chevron" size={16} />
        </Link>
      ) : null}
    </section>
  );
}
