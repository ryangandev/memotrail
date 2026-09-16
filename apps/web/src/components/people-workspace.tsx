"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { savePerson, trashPerson } from "@/app/people/actions";
import common from "@/app/homes/page.module.css";
import { PageFrame } from "@/components/page-frame";
import { Icon } from "@/components/icon";
import {
  personEntryTitle,
  type Person,
  type PersonEntry,
} from "@/lib/data/person";
import styles from "@/app/people/page.module.css";

export function PeopleWorkspace({
  people,
  entries,
  error,
  page,
  focused = false,
}: {
  people: Person[];
  entries: PersonEntry[];
  error: string | null;
  page: number;
  focused?: boolean;
}) {
  const router = useRouter();
  const [selected, setSelected] = useState<Person | null | undefined>(
    focused ? people[0] : undefined,
  );
  const connectionCount = people.reduce(
    (total, person) => total + person.linked_entries.length,
    0,
  );
  return (
    <PageFrame variant="wide">
      <header className={common.pageHeader}>
        <div>
          <p className={common.eyebrow}>The people in your story</p>
          <h1>People</h1>
          <p>Keep a little context for the people who shaped each chapter.</p>
        </div>
        <button
          aria-label="Add Person"
          className={common.addButton}
          onClick={() => setSelected(null)}
          type="button"
        >
          <Icon name="plus" />
          <span>Add Person</span>
        </button>
      </header>

      <div className={common.summary} aria-label="People summary">
        <span>{countLabel(people.length, "person", "people")}</span>
        <span aria-hidden="true">·</span>
        <span>{countLabel(connectionCount, "connected Item")}</span>
      </div>

      {error ? (
        <div className={common.message} role="alert">
          <Icon name="person" size={22} />
          <div>
            <strong>People unavailable</strong>
            <p>{error}</p>
          </div>
        </div>
      ) : null}
      {!people.length && !error ? (
        <button
          className={common.emptyState}
          onClick={() => setSelected(null)}
          type="button"
        >
          <span className={common.emptyMark}>
            <Icon name="person" size={24} />
          </span>
          <strong>Remember the first person in your story</strong>
          <span>
            Start with a name. Relationship context, notes, and connected Items
            can be added whenever they become useful.
          </span>
        </button>
      ) : null}
      <div className={styles.peopleGrid}>
        {people.map((person) => (
          <button
            className={styles.card}
            key={person.id}
            onClick={() => setSelected(person)}
          >
            <span className={styles.initial}>
              {Array.from(person.name)[0]?.toUpperCase()}
            </span>
            <h2>{person.name}</h2>
            <p>{person.relationship_label || "A person in your story"}</p>
            <p className={styles.preview}>{person.notes}</p>
            <small>{person.linked_entries.length} connected Items</small>
          </button>
        ))}
      </div>
      <nav className={styles.pagination} aria-label="People pages">
        {page > 1 ? (
          <Link href={`/people?page=${page - 1}`}>Previous</Link>
        ) : null}
        {(people[0]?.total_count ?? 0) > page * 100 ? (
          <Link href={`/people?page=${page + 1}`}>Next</Link>
        ) : null}
      </nav>
      {selected !== undefined ? (
        <PersonEditor
          key={selected?.id ?? "new"}
          person={selected}
          entries={entries}
          onClose={() => {
            setSelected(undefined);
            if (focused) router.replace("/people", { scroll: false });
          }}
        />
      ) : null}
    </PageFrame>
  );
}

function PersonEditor({
  person,
  entries,
  onClose,
}: {
  person: Person | null;
  entries: PersonEntry[];
  onClose: () => void;
}) {
  const router = useRouter();
  const dialogRef = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const dialog = dialogRef.current;
    dialog?.showModal();
    return () => dialog?.close();
  }, []);
  const [name, setName] = useState(person?.name ?? "");
  const [relationshipLabel, setRelationshipLabel] = useState(
    person?.relationship_label ?? "",
  );
  const [notes, setNotes] = useState(person?.notes ?? "");
  const [entryIds, setEntryIds] = useState(
    person?.linked_entries.map((e) => e.id) ?? [],
  );
  const [entryId, setEntryId] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const options = new Map(
    [...entries, ...(person?.linked_entries ?? [])].map((e) => [e.id, e]),
  );
  async function mutate(remove = false) {
    if (busy) return;
    if (
      remove &&
      !window.confirm(
        `Move ${person?.name} to Trash? You can restore it later.`,
      )
    )
      return;
    setBusy(true);
    setMessage(null);
    try {
      const failure =
        remove && person
          ? await trashPerson(person.id, person.revision)
          : await savePerson({
              id: person?.id ?? null,
              revision: person?.revision ?? null,
              name,
              relationshipLabel,
              notes,
              entryIds,
            });
      if (failure) setMessage(failure);
      else {
        router.refresh();
        onClose();
      }
    } catch {
      setMessage(
        "Could not reach MemoTrail. Your edits are still here; try again when online.",
      );
    } finally {
      setBusy(false);
    }
  }
  return (
    <dialog
      ref={dialogRef}
      className={styles.dialog}
      aria-labelledby="person-title"
      onCancel={(e) => {
        e.preventDefault();
        if (!busy) onClose();
      }}
    >
      <form
        onSubmit={(e) => {
          e.preventDefault();
          void mutate();
        }}
      >
        <header className={styles.dialogHeader}>
          <h2 id="person-title">{person ? "Edit Person" : "New Person"}</h2>
          <button
            type="button"
            disabled={busy}
            onClick={onClose}
            aria-label="Close Person editor"
          >
            Close
          </button>
        </header>
        <fieldset disabled={busy}>
          <label>
            Name
            <input
              autoFocus
              required
              maxLength={200}
              value={name}
              onChange={(e) => setName(e.target.value)}
            />
          </label>
          <label>
            Relationship <small>Optional</small>
            <input
              maxLength={200}
              placeholder="Friend, family, mentor..."
              value={relationshipLabel}
              onChange={(e) => setRelationshipLabel(e.target.value)}
            />
          </label>
          <label>
            Notes <small>Optional</small>
            <textarea
              rows={4}
              maxLength={10000}
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
            />
          </label>
          <h3>Connected Items</h3>
          {entryIds.map((id) => {
            const entry = options.get(id);
            return (
              <div key={id} className={styles.link}>
                <details>
                  <summary>
                    {entry ? personEntryTitle(entry) : "Linked Item"}
                    {entry?.is_deleted ? " (in Trash)" : ""}
                  </summary>
                  <p>{entry?.body}</p>
                </details>
                <button
                  type="button"
                  aria-label={`Unlink ${entry ? personEntryTitle(entry) : "Item"}`}
                  onClick={() => setEntryIds(entryIds.filter((i) => i !== id))}
                >
                  Unlink
                </button>
              </div>
            );
          })}
          <label>
            Link an Item
            <select
              value={entryId}
              onChange={(e) => setEntryId(e.target.value)}
            >
              <option value="">Choose from recent Items</option>
              {entries
                .filter((e) => !entryIds.includes(e.id))
                .map((e) => (
                  <option key={e.id} value={e.id}>
                    {personEntryTitle(e)}
                  </option>
                ))}
            </select>
          </label>
          <button
            type="button"
            disabled={!entryId || entryIds.length >= 100}
            onClick={() => {
              setEntryIds([...entryIds, entryId]);
              setEntryId("");
            }}
          >
            Link Item
          </button>
        </fieldset>
        {message ? <p role="alert">{message}</p> : null}
        <footer className={styles.footer}>
          {person ? (
            <div>
              <button
                type="button"
                disabled={busy || person.linked_entries.length > 0}
                onClick={() => void mutate(true)}
              >
                Move to Trash
              </button>
              {person.linked_entries.length > 0 ? (
                <small>
                  Unlink every Item and save before removing this Person.
                </small>
              ) : null}
            </div>
          ) : (
            <span />
          )}
          <button disabled={busy} type="submit">
            {busy ? "Saving..." : "Save changes"}
          </button>
        </footer>
      </form>
    </dialog>
  );
}

function countLabel(count: number, singular: string, plural = `${singular}s`) {
  return `${count} ${count === 1 ? singular : plural}`;
}
