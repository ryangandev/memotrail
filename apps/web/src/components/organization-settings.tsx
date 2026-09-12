"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import {
  saveOrganization,
  trashCollection,
} from "@/app/settings/organization/actions";
import {
  validOrganizationInput,
  type OrganizationItem,
  type OrganizationKind,
  type OrganizationInput,
} from "@/lib/data/organization";
import styles from "@/app/settings/organization/page.module.css";
export function OrganizationSettings({
  items,
  kind,
}: {
  items: OrganizationItem[];
  kind: OrganizationKind;
}) {
  const router = useRouter();
  const [adding, setAdding] = useState(false);
  const [generation, setGeneration] = useState(0);
  const [notice, setNotice] = useState<string | null>(null);
  const label = kind === "collection" ? "Collection" : "tag";
  return (
    <>
      <div className={styles.actions}>
        <button onClick={() => setAdding(!adding)}>
          {adding ? "Cancel new item" : `Add ${label}`}
        </button>
        <button
          onClick={() => {
            setGeneration((v) => v + 1);
            router.refresh();
          }}
        >
          Reload items
        </button>
      </div>
      <p className={styles.hint}>
        {kind === "collection"
          ? "Lower order numbers appear first. "
          : "Tags sort alphabetically. "}
        Reloading discards unsaved edits. Duplicate names are never silently
        merged.
      </p>
      {notice && <p role="status">{notice}</p>}
      {adding && (
        <OrganizationForm
          key={`new:${generation}`}
          kind={kind}
          onSaved={() => {
            setAdding(false);
            setNotice(
              `${label} created. Clear your search if it is not visible here.`,
            );
          }}
        />
      )}
      <div className={styles.list}>
        {items.map((item) => (
          <OrganizationForm
            key={`${item.id}:${item.revision}:${generation}`}
            item={item}
            kind={kind}
          />
        ))}
        {items.length === 0 && (
          <p>
            No matching {kind === "tag" ? "tags" : "Collections"}. Add one or
            change your search.
          </p>
        )}
      </div>
    </>
  );
}
function OrganizationForm({
  item,
  kind,
  onSaved,
}: {
  item?: OrganizationItem;
  kind: OrganizationKind;
  onSaved?: () => void;
}) {
  const [name, setName] = useState(item?.name ?? "");
  const [order, setOrder] = useState(String(item?.sort_order ?? 0));
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const label = kind === "collection" ? "Collection" : "tag";
  const input: OrganizationInput = {
    kind,
    id: item?.id ?? null,
    revision: item?.revision ?? null,
    name,
    order: kind === "tag" ? 0 : order.trim() ? Number(order) : NaN,
  };
  async function submit(remove = false) {
    if (busy || (!remove && !validOrganizationInput(input))) return;
    if (
      remove &&
      !window.confirm(
        `Move “${item?.name}” to Trash? Your Entries and photos stay in the archive. You can restore this Collection and its grouping later.`,
      )
    )
      return;
    setBusy(true);
    setMessage(null);
    try {
      const error = remove
        ? await trashCollection({
            ...input,
            name: item!.name,
            order: item!.sort_order,
          })
        : await saveOrganization(input);
      setMessage(error ?? "Saved.");
      if (!error) onSaved?.();
    } catch {
      setMessage("Could not connect. Your edits are still here to retry.");
    } finally {
      setBusy(false);
    }
  }
  return (
    <form
      className={styles.card}
      aria-label={item ? `Edit ${item.name}` : `New ${label}`}
      onSubmit={(e) => {
        e.preventDefault();
        void submit();
      }}
    >
      <div className={styles.cardHeading}>
        <h2>{item?.name ?? `New ${label}`}</h2>
        <span>
          {item
            ? `${item.entry_count} ${item.entry_count === 1 ? "Entry" : "Entries"}`
            : "Start a new thread"}
        </span>
      </div>
      <fieldset disabled={busy}>
        <div
          className={kind === "collection" ? styles.fields : styles.singleField}
        >
          <label>
            Name
            <input
              value={name}
              onChange={(e) => setName(e.target.value)}
              maxLength={80}
              required
            />
          </label>
          {kind === "collection" && (
            <label>
              Order
              <input
                type="number"
                value={order}
                onChange={(e) => setOrder(e.target.value)}
                min={-1000000}
                max={1000000}
                step={1}
                required
              />
            </label>
          )}
        </div>
        {item?.system_key === "bucket_list" && (
          <p className={styles.hint}>
            Bucket List Collection. Renaming preserves its Goal milestone
            behavior.
          </p>
        )}
        <div className={styles.actions}>
          <button disabled={!validOrganizationInput(input)}>
            {busy ? "Saving…" : item ? "Save changes" : `Create ${label}`}
          </button>
          {item && kind === "collection" && (
            <button type="button" onClick={() => void submit(true)}>
              Move to Trash
            </button>
          )}
        </div>
      </fieldset>
      {message && <p role="status">{message}</p>}
    </form>
  );
}
