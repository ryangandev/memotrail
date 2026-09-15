"use client";

import { useEffect, useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { createPortal } from "react-dom";
import {
  deleteUnusedTag,
  mergeTags,
  saveOrganization,
  trashCollection,
} from "@/app/organization/actions";
import { Icon } from "@/components/icon";
import {
  validOrganizationInput,
  type OrganizationItem,
  type OrganizationKind,
} from "@/lib/data/organization";
import styles from "./organization-control.module.css";

export function OrganizationControl({
  item,
  items = [],
  kind,
}: {
  item?: OrganizationItem;
  items?: OrganizationItem[];
  kind: OrganizationKind;
}) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [name, setName] = useState(item?.name ?? "");
  const [order, setOrder] = useState(String(item?.sort_order ?? 0));
  const [targetId, setTargetId] = useState("");
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
    if (!open) return;
    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape" && !busy) setOpen(false);
    }
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [busy, open]);

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

  return (
    <>
      <button
        aria-label={item ? `Edit ${item.name}` : `New ${label}`}
        className={item ? styles.editTrigger : styles.newTrigger}
        onClick={() => {
          setMessage(null);
          setOpen(true);
        }}
        type="button"
      >
        <Icon name={item ? "more" : "plus"} size={17} />
        {!item ? `New ${label}` : null}
      </button>

      {open
        ? createPortal(
            <div
              className={styles.backdrop}
              data-organization-overlay
              onMouseDown={(event) => {
                if (event.currentTarget === event.target && !busy)
                  setOpen(false);
              }}
            >
              <section
                aria-labelledby={`organization-control-${item?.id ?? kind}`}
                aria-modal="true"
                className={styles.dialog}
                role="dialog"
              >
                <header>
                  <div>
                    <p>{item ? `Edit ${label}` : `New ${label}`}</p>
                    <h2 id={`organization-control-${item?.id ?? kind}`}>
                      {item?.name ?? `Create a ${label}`}
                    </h2>
                  </div>
                  <button
                    aria-label="Close organization editor"
                    disabled={busy}
                    onClick={() => setOpen(false)}
                    type="button"
                  >
                    <Icon name="close" size={20} />
                  </button>
                </header>

                <form onSubmit={submit}>
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
                  <footer>
                    <div>
                      {item && kind === "collection" ? (
                        <button
                          className={styles.danger}
                          disabled={busy}
                          onClick={() => void remove()}
                          type="button"
                        >
                          Move to Trash
                        </button>
                      ) : null}
                      {item && kind === "tag" && item.entry_count === 0 ? (
                        <button
                          className={styles.danger}
                          disabled={busy}
                          onClick={() => void remove()}
                          type="button"
                        >
                          Delete unused tag
                        </button>
                      ) : null}
                    </div>
                    <div>
                      <button
                        className={styles.cancel}
                        disabled={busy}
                        onClick={() => setOpen(false)}
                        type="button"
                      >
                        Cancel
                      </button>
                      <button
                        className={styles.save}
                        disabled={busy || !validOrganizationInput(input)}
                        type="submit"
                      >
                        {busy
                          ? "Saving..."
                          : item
                            ? "Save changes"
                            : `Create ${label}`}
                      </button>
                    </div>
                  </footer>
                </form>

                {item && kind === "tag" && item.entry_count > 0 ? (
                  <div className={styles.mergePanel}>
                    <div>
                      <strong>Merge this tag</strong>
                      <p>
                        This tag is used by{" "}
                        {countLabel(item.entry_count, "Entry")}. Merge it to
                        preserve every assignment.
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
                    <button
                      disabled={busy || !targetId}
                      onClick={() => void merge()}
                      type="button"
                    >
                      Merge tag
                    </button>
                  </div>
                ) : null}
              </section>
            </div>,
            document.body,
          )
        : null}
    </>
  );
}

function countLabel(count: number, singular: string) {
  return `${count} ${count === 1 ? singular : `${singular}s`}`;
}
