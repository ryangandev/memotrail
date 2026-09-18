"use client";
import { Dialog } from "@/components/dialog";
import { Button, IconButton } from "@/components/button";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState, type FormEvent, type ReactNode } from "react";
import {
  deleteUnusedTag,
  loadTagEntryPreviews,
  mergeTags,
  saveOrganization,
  trashCollection,
} from "@/app/organization/actions";
import { Icon } from "@/components/icon";
import {
  validOrganizationInput,
  type OrganizationItem,
  type OrganizationKind,
  type TagEntryPreviewResult,
} from "@/lib/data/organization";
import styles from "./organization-control.module.css";

export function OrganizationControl({
  item,
  items = [],
  kind,
  trigger,
  triggerClassName,
}: {
  item?: OrganizationItem;
  items?: OrganizationItem[];
  kind: OrganizationKind;
  trigger?: ReactNode;
  triggerClassName?: string;
}) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [name, setName] = useState(item?.name ?? "");
  const [order, setOrder] = useState(String(item?.sort_order ?? 0));
  const [targetId, setTargetId] = useState("");
  const [tagPreview, setTagPreview] = useState<TagEntryPreviewResult | null>(
    null,
  );
  const label = kind === "collection" ? "Collection" : "Tag";
  const mergeTargets = items.filter((candidate) => candidate.id !== item?.id);
  const input = {
    id: item?.id ?? null,
    kind,
    name,
    order: kind === "tag" ? 0 : Number(order),
    revision: item?.revision ?? null,
  } as const;

  useEffect(() => {
    if (!open || kind !== "tag" || !item) return;
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
  }, [item, kind, open]);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (busy || !validOrganizationInput(input)) return;
    await run(() => saveOrganization(input));
  }

  async function remove() {
    if (!item || busy) return;
    const confirmed = window.confirm(
      kind === "collection"
        ? `Move “${item.name}” to Trash? Entries stay in your archive and the Collection can be restored.`
        : `Delete the unused tag “${item.name}”?`,
    );
    if (!confirmed) return;
    await run(() =>
      kind === "collection"
        ? trashCollection(input)
        : deleteUnusedTag({ id: item.id, revision: item.revision }),
    );
  }

  async function merge() {
    const target = mergeTargets.find((candidate) => candidate.id === targetId);
    if (!item || !target || busy) return;
    if (
      !window.confirm(
        `Merge “${item.name}” into “${target.name}”? Every Entry will use “${target.name}” and “${item.name}” will be removed.`,
      )
    ) {
      return;
    }
    await run(() =>
      mergeTags({
        source: { id: item.id, revision: item.revision },
        target: { id: target.id, revision: target.revision },
      }),
    );
  }

  async function run(action: () => Promise<string | null>) {
    setBusy(true);
    setMessage(null);
    try {
      const error = await action();
      if (error) {
        setMessage(error);
        return;
      }
      setOpen(false);
      router.refresh();
    } catch {
      setMessage("Could not connect. Your changes are still here to retry.");
    } finally {
      setBusy(false);
    }
  }

  function openEditor() {
    setMessage(null);
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
                : `New ${label}`
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
          variant="ghost"
          onClick={openEditor}
        >
          <Icon name="more" size={17} />
        </IconButton>
      ) : (
        <Button onClick={openEditor}>
          <Icon name="plus" size={17} /> New {label}
        </Button>
      )}

      {open ? (
        <Dialog
          open
          onOpenChange={(nextOpen) => {
            if (!nextOpen) (() => setOpen(false))();
          }}
          title={<>{item?.name ?? `Create a ${label}`}</>}
          titleId={`organization-control-${item?.id ?? kind}`}
          eyebrow={<>{item ? `Edit ${label}` : `New ${label}`}</>}
          headerContent={
            <>
              {item && kind === "tag" ? (
                <span className={styles.usageCount}>
                  Used by {countLabel(item.entry_count, "Entry")}
                </span>
              ) : null}
            </>
          }
          closeLabel="Close organization editor"
          busy={busy}
          size="standard"
          footer={
            <div className={styles.editorActions}>
              <div>
                {item && kind === "collection" ? (
                  <Button
                    variant="danger"

                    disabled={busy}
                    onClick={() => void remove()}
                    type="button"
                  >
                    Move to Trash
                  </Button>
                ) : null}
                {item && kind === "tag" && item.entry_count === 0 ? (
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
                  form="organization-control-form"
                  variant="primary"

                  disabled={busy || !validOrganizationInput(input)}
                  type="submit"
                >
                  {busy
                    ? "Saving..."
                    : item
                      ? "Save changes"
                      : `Create ${label}`}
                </Button>
              </div>
            </div>
          }
        >
          <div className={styles.editorContent}>
            <form id="organization-control-form" onSubmit={submit}>
              <fieldset disabled={busy}>
                <label>
                  <span>Name *</span>
                  <input
                    autoFocus
                    maxLength={kind === "tag" ? 60 : 80}
                    onChange={(event) => setName(event.target.value)}
                    required
                    value={name}
                  />
                </label>
                {kind === "collection" ? (
                  <label>
                    <span>Display order *</span>
                    <input
                      max={1000000}
                      min={-1000000}
                      onChange={(event) => setOrder(event.target.value)}
                      required
                      step={1}
                      type="number"
                      value={order}
                    />
                  </label>
                ) : null}
              </fieldset>
              {item?.system_key === "bucket_list" ? (
                <p className={styles.helper}>
                  This is your Bucket List Collection. Renaming it preserves
                  Goal milestone behavior.
                </p>
              ) : null}
              {message ? (
                <p className={styles.message} role="alert">
                  {message}
                </p>
              ) : null}
            </form>
            {item && kind === "tag" && item.entry_count > 0 ? (
              <div className={styles.mergePanel}>
                <div>
                  <strong>Merge this tag</strong>
                  <p>
                    This tag is used by {countLabel(item.entry_count, "Entry")}.
                    Merge it to preserve every assignment.
                  </p>
                </div>
                <label>
                  <span>Destination tag</span>
                  <select
                    disabled={busy || mergeTargets.length === 0}
                    onChange={(event) => setTargetId(event.target.value)}
                    value={targetId}
                  >
                    <option value="">Choose a tag</option>
                    {mergeTargets.map((candidate) => (
                      <option key={candidate.id} value={candidate.id}>
                        #{candidate.name} ({candidate.entry_count})
                      </option>
                    ))}
                  </select>
                </label>
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
            {item && kind === "tag" ? (
              <TagEntryList
                count={item.entry_count}
                name={item.name}
                preview={tagPreview}
              />
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
  const allEntriesHref = `/search?tag=${encodeURIComponent(name)}`;

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
          <span />
          <span />
          <span />
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
                  {entry.type} · {entry.date}
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

function countLabel(count: number, singular: string) {
  const plural = singular.endsWith("y")
    ? `${singular.slice(0, -1)}ies`
    : `${singular}s`;
  return `${count} ${count === 1 ? singular : plural}`;
}
