"use client";
import Link from "next/link";
import { useEffect, useState } from "react";
import { loadHabitEntryChoices } from "@/app/habits/actions";
import {
  habitEntryTitle,
  type HabitEntryChoice,
  type HabitEntryChoices,
} from "@/lib/data/habit-entry-links";
import styles from "./habit-entry-picker.module.css";

export function HabitEntryPicker({
  habitId,
  localDate,
  entryId,
  disabled,
  onChange,
}: {
  habitId: string;
  localDate: string;
  entryId: string | null;
  disabled: boolean;
  onChange: (id: string | null) => void;
}) {
  const [query, setQuery] = useState("");
  const [search, setSearch] = useState("");
  const [page, setPage] = useState(0);
  const [reload, setReload] = useState(0);
  const [busy, setBusy] = useState(true);
  const [data, setData] = useState<HabitEntryChoices | null>(null);
  const [picked, setPicked] = useState<HabitEntryChoice | null>(null);
  const [error, setError] = useState(false);
  useEffect(() => {
    let active = true;
    loadHabitEntryChoices({ habitId, localDate, query: search, page })
      .then((value) => {
        if (active) {
          setData(value);
          setError(false);
        }
      })
      .catch(() => {
        if (active) {
          setData(null);
          setError(true);
        }
      })
      .finally(() => {
        if (active) setBusy(false);
      });
    return () => {
      active = false;
    };
  }, [habitId, localDate, search, page, reload]);
  const selected = [picked, data?.selected, ...(data?.items ?? [])].find(
    (row) => row?.id === entryId,
  );
  return (
    <section className={styles.panel} aria-label="Linked Entry">
      <h3>Linked Entry</h3>
      <p>
        Optional context for this check-in. Changes apply only when you save;
        the original writing stays unchanged.
      </p>
      {entryId ? (
        <div className={styles.selection}>
          <Link
            href={`/history?entry=${entryId}`}
            target="_blank"
            rel="noopener noreferrer"
          >
            {selected ? habitEntryTitle(selected) : "Open linked Entry"}
          </Link>
          {selected?.is_deleted && (
            <span>In Trash. This link is kept unless you remove it.</span>
          )}
          <button
            type="button"
            disabled={disabled}
            onClick={() => onChange(null)}
          >
            Remove link
          </button>
        </div>
      ) : (
        <p>No Entry linked.</p>
      )}
      <label>
        Find an Entry
        <input
          value={query}
          maxLength={200}
          disabled={disabled}
          placeholder="Title or words, including Chinese"
          onChange={(event) => setQuery(event.target.value)}
          onKeyDown={(event) => {
            if (event.key === "Enter") {
              event.preventDefault();
              if (!busy) {
                setBusy(true);
                setSearch(query.trim());
                setPage(0);
                setReload((v) => v + 1);
              }
            }
          }}
        />
      </label>
      <button
        type="button"
        disabled={disabled || busy}
        onClick={() => {
          setBusy(true);
          setSearch(query.trim());
          setPage(0);
          setReload((v) => v + 1);
        }}
      >
        Search Entries
      </button>
      {busy ? (
        <p role="status">Loading Entries...</p>
      ) : error ? (
        <p role="alert">
          Entries could not load. Search again to retry. Your existing link has
          not changed.
        </p>
      ) : (
        <>
          {!data?.items.length && <p>No matching active Entries.</p>}
          <ul>
            {data?.items.map((row) => (
              <li key={row.id}>
                <button
                  type="button"
                  disabled={disabled || entryId === row.id}
                  onClick={() => {
                    setPicked(row);
                    onChange(row.id);
                  }}
                >
                  Link {habitEntryTitle(row)}
                </button>
              </li>
            ))}
          </ul>
          <div className={styles.pagination}>
            <button
              type="button"
              disabled={disabled || page === 0}
              onClick={() => {
                setBusy(true);
                setPage((v) => v - 1);
              }}
            >
              Previous Entries
            </button>
            <span>Page {page + 1}</span>
            <button
              type="button"
              disabled={disabled || (page + 1) * 20 >= (data?.total_count ?? 0)}
              onClick={() => {
                setBusy(true);
                setPage((v) => v + 1);
              }}
            >
              Next Entries
            </button>
          </div>
        </>
      )}
    </section>
  );
}
