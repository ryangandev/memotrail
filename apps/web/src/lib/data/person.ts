import type { WikiItemKind } from "./wiki-item";

export type PersonEntry = {
  id: string;
  title: string | null;
  body: string;
  item_kind: WikiItemKind;
  item_subtype: string;
  is_deleted?: boolean;
};

export type Person = {
  id: string;
  name: string;
  relationship_label: string | null;
  notes: string | null;
  revision: number;
  linked_entries: PersonEntry[];
  total_count: number;
};

export type PersonInput = {
  id: string | null;
  revision: number | null;
  name: string;
  relationshipLabel: string;
  notes: string;
  entryIds: string[];
};

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function parsePersonInput(value: unknown): PersonInput | null {
  if (!value || typeof value !== "object") return null;
  const v = value as Record<string, unknown>;
  if (
    typeof v.name !== "string" ||
    !v.name.trim() ||
    v.name.trim().length > 200 ||
    typeof v.relationshipLabel !== "string" ||
    v.relationshipLabel.length > 200 ||
    typeof v.notes !== "string" ||
    v.notes.length > 10_000 ||
    !Array.isArray(v.entryIds) ||
    v.entryIds.length > 100 ||
    !v.entryIds.every((id) => typeof id === "string" && uuid.test(id))
  )
    return null;
  if (
    v.id === null
      ? v.revision !== null
      : typeof v.id !== "string" ||
        !uuid.test(v.id) ||
        !Number.isSafeInteger(v.revision) ||
        Number(v.revision) < 1
  )
    return null;
  return {
    id: v.id as string | null,
    revision: v.revision as number | null,
    name: v.name.trim(),
    relationshipLabel: v.relationshipLabel.trim(),
    notes: v.notes.trim(),
    entryIds: [
      ...new Set((v.entryIds as string[]).map((id) => id.toLowerCase())),
    ],
  };
}

export function personEntryTitle(entry: PersonEntry) {
  return (
    entry.title?.trim() || entry.body.trim().slice(0, 80) || "Untitled Entry"
  );
}
