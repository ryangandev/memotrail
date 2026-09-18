"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
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

  useEffect(() => {
    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape" && !busy) onClose();
    }
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [busy, onClose]);

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
    <div
      aria-modal="true"
      aria-labelledby="person-title"
      className={common.dialogBackdrop}
      onMouseDown={(event) => {
        if (event.currentTarget === event.target && !busy) onClose();
      }}
      role="dialog"
    >
      <div className={common.dialogPanel}>
        <header className={common.dialogHeader}>
          <div>
            <p>{person ? "Edit Person" : "New Person"}</p>
            <h2 id="person-title">
              {person ? person.name : "Keep someone in your story"}
            </h2>
          </div>
          <button
            aria-label="Close Person editor"
            disabled={busy}
            onClick={onClose}
            type="button"
          >
            ×
          </button>
        </header>
        <form
          onSubmit={(event) => {
            event.preventDefault();
            void mutate();
          }}
        >
          <div className={common.formGrid}>
            <fieldset className={common.formSection} disabled={busy}>
              <legend>Person details</legend>
              <label className={common.fullField}>
                <span>
                  Name <span aria-hidden="true">*</span>
                </span>
                <input
                  aria-label="Name"
                  autoFocus
                  maxLength={200}
                  onChange={(event) => setName(event.target.value)}
                  required
                  value={name}
                />
              </label>
              <label className={common.fullField}>
                <span>Relationship</span>
                <input
                  maxLength={200}
                  onChange={(event) => setRelationshipLabel(event.target.value)}
                  placeholder="Friend, family, mentor..."
                  value={relationshipLabel}
                />
              </label>
              <label className={common.fullField}>
                <span>Notes</span>
                <textarea
                  maxLength={10000}
                  onChange={(event) => setNotes(event.target.value)}
                  rows={4}
                  value={notes}
                />
              </label>
            </fieldset>

            <fieldset
              className={`${common.formSection} ${styles.connectionsSection}`}
              disabled={busy}
            >
              <legend>Connected Items</legend>
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
                      aria-label={`Unlink ${entry ? personEntryTitle(entry) : "Item"}`}
                      onClick={() =>
                        setEntryIds(entryIds.filter((item) => item !== id))
                      }
                      type="button"
                    >
                      Unlink
                    </button>
                  </div>
                );
              })}
              <div className={styles.linkPicker}>
                <label>
                  <span>Link an Item</span>
                  <select
                    onChange={(event) => setEntryId(event.target.value)}
                    value={entryId}
                  >
                    <option value="">Choose from recent Items</option>
                    {entries
                      .filter((entry) => !entryIds.includes(entry.id))
                      .map((entry) => (
                        <option key={entry.id} value={entry.id}>
                          {personEntryTitle(entry)}
                        </option>
                      ))}
                  </select>
                </label>
                <button
                  disabled={!entryId || entryIds.length >= 100}
                  onClick={() => {
                    setEntryIds([...entryIds, entryId]);
                    setEntryId("");
                  }}
                  type="button"
                >
                  Link Item
                </button>
              </div>
            </fieldset>
          </div>
          {message ? (
            <p className={common.formMessage} role="alert">
              {message}
            </p>
          ) : null}
          <footer className={common.dialogFooter}>
            <div>
              {person ? (
                <>
                  <button
                    className={common.trashButton}
                    disabled={busy || person.linked_entries.length > 0}
                    onClick={() => void mutate(true)}
                    type="button"
                  >
                    Move to Trash
                  </button>
                  {person.linked_entries.length > 0 ? (
                    <small className={styles.trashNote}>
                      Unlink every Item and save before removing this Person.
                    </small>
                  ) : null}
                </>
              ) : null}
            </div>
            <div>
              <button
                className={common.cancelButton}
                disabled={busy}
                onClick={onClose}
                type="button"
              >
                Cancel
              </button>
              <button
                className={common.saveButton}
                disabled={busy}
                type="submit"
              >
                {busy ? "Saving..." : person ? "Save changes" : "Add Person"}
              </button>
            </div>
          </footer>
        </form>
      </div>
    </div>
  );
}

function countLabel(count: number, singular: string, plural = `${singular}s`) {
  return `${count} ${count === 1 ? singular : plural}`;
}
