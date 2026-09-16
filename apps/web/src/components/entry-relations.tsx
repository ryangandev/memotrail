"use client";
import Link from "next/link";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import {
  changeEntryRelation,
  loadEntryRelations,
} from "@/app/history/relation-actions";
import { historyTitle } from "@/lib/data/history";
import {
  relationModes,
  relationModeLabels,
  type EntryRelations,
  type RelatedEntry,
  type RelationMode,
} from "@/lib/data/entry-relations";
import { wikiItemIdentityLabel } from "@/lib/data/wiki-item";
import styles from "./entry-relations.module.css";
export function EntryRelationsPanel({ entryID }: { entryID: string }) {
  const router = useRouter();
  const [mode, setMode] = useState<RelationMode>("outgoing");
  const [query, setQuery] = useState("");
  const [search, setSearch] = useState("");
  const [page, setPage] = useState(0);
  const [refresh, setRefresh] = useState(0);
  const [data, setData] = useState<EntryRelations | null>(null);
  const [busy, setBusy] = useState(true);
  const [message, setMessage] = useState<string | null>(null);
  useEffect(() => {
    let active = true;
    loadEntryRelations({ entryID, mode, query: search, page })
      .then((value) => {
        if (active) {
          setData(value);
          setMessage(null);
        }
      })
      .catch(() => {
        if (active) {
          setData(null);
          setMessage("Links could not load. Refresh to try again.");
        }
      })
      .finally(() => {
        if (active) setBusy(false);
      });
    return () => {
      active = false;
    };
  }, [entryID, mode, search, page, refresh]);
  function reload() {
    setBusy(true);
    setRefresh((v) => v + 1);
  }
  async function change(row: RelatedEntry, linked: boolean) {
    if (
      !data ||
      busy ||
      (!linked &&
        !confirm(
          `Unlink ${historyTitle(row)}? Neither Item is deleted. This change can be restored through this Item's history.`,
        ))
    )
      return;
    setBusy(true);
    setMessage(null);
    try {
      const error = await changeEntryRelation({
        entryID,
        targetID: row.entry_id,
        revision: data.revision,
        linked,
      });
      if (error) {
        setMessage(error);
        setBusy(false);
      } else {
        if (!linked) {
          setData({
            ...data,
            items: data.items.filter((item) => item.entry_id !== row.entry_id),
            revision: data.revision + 1,
            total_count: Math.max(0, data.total_count - 1),
          });
          setBusy(false);
        }
        setMode("outgoing");
        setQuery("");
        setSearch("");
        setPage(0);
        setRefresh((v) => v + 1);
        router.refresh();
      }
    } catch {
      setMessage("Could not confirm the change. Refresh before retrying.");
      setBusy(false);
    }
  }
  return (
    <section className={styles.panel} aria-label="Related Items">
      <h3>Related Items</h3>
      <p>
        Connect existing writing without copying it. Link changes save
        immediately and stay in this Item&apos;s history.
      </p>
      <div className={styles.controls} aria-label="Relationship views">
        {relationModes.map((value) => (
          <button
            key={value}
            type="button"
            disabled={busy}
            aria-pressed={mode === value}
            onClick={() => {
              setBusy(true);
              setMode(value);
              setPage(0);
              setQuery("");
              setSearch("");
              setRefresh((v) => v + 1);
            }}
          >
            {relationModeLabels[value]}
          </button>
        ))}
      </div>
      <form
        className={styles.search}
        onSubmit={(event) => {
          event.preventDefault();
          setBusy(true);
          setPage(0);
          setSearch(query.trim());
          setRefresh((v) => v + 1);
        }}
      >
        <label>
          Search related Items
          <input
            value={query}
            maxLength={200}
            onChange={(e) => setQuery(e.target.value)}
            disabled={busy}
            placeholder="Title or words, including Chinese"
          />
        </label>
        <button disabled={busy}>Search</button>
      </form>
      {mode === "incoming" && (
        <p>
          These Items link here. Open the source Item to change its link.
        </p>
      )}
      {mode === "candidates" && (
        <p>
          Choose an active Item to link. Existing outgoing links are omitted.
        </p>
      )}
      {busy ? (
        <p role="status">Loading links...</p>
      ) : (
        data && (
          <>
            {!data.items.length && (
              <p>
                {mode === "candidates"
                  ? "No matching Items to link."
                  : "No matching linked Items."}
              </p>
            )}
            <ul className={styles.list}>
              {data.items.map((row) => (
                <li key={row.entry_id}>
                  <div>
                    <Link href={`/history?entry=${row.entry_id}`}>
                      {historyTitle(row)}
                    </Link>
                    <small>
                      {wikiItemIdentityLabel(row.item_kind, row.item_subtype)}
                      {row.is_deleted ? " · In Trash" : ""}
                    </small>
                    <p>{row.excerpt}</p>
                  </div>
                  {mode !== "incoming" && (
                    <button
                      type="button"
                      disabled={busy}
                      aria-label={`${mode === "candidates" ? "Link" : "Unlink"} ${historyTitle(row)}`}
                      onClick={() => void change(row, mode === "candidates")}
                    >
                      {mode === "candidates" ? "Link Item" : "Unlink"}
                    </button>
                  )}
                </li>
              ))}
            </ul>
            <div className={styles.controls} aria-label="Relationship pages">
              <button
                type="button"
                disabled={page === 0}
                onClick={() => {
                  setBusy(true);
                  setPage(page - 1);
                }}
              >
                Previous links
              </button>
              <span>
                Page {page + 1} · {data.total_count}{" "}
                {data.total_count === 1 ? "Item" : "Items"}
              </span>
              <button
                type="button"
                disabled={(page + 1) * 20 >= data.total_count}
                onClick={() => {
                  setBusy(true);
                  setPage(page + 1);
                }}
              >
                Next links
              </button>
            </div>
          </>
        )
      )}
      {message && <p role="alert">{message}</p>}
      <button type="button" disabled={busy} onClick={reload}>
        Refresh links
      </button>
    </section>
  );
}
