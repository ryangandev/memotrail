import { validHistoryID } from "./history";
import type { WikiItemKind } from "./wiki-item";
export const relationModes = ["outgoing", "incoming", "candidates"] as const;
export type RelationMode = (typeof relationModes)[number];
export const relationModeLabels: Record<RelationMode, string> = {
  outgoing: "Linked Items",
  incoming: "Linked from",
  candidates: "Find Items",
};
export type RelatedEntry = {
  entry_id: string;
  title: string | null;
  excerpt: string;
  item_kind: WikiItemKind;
  item_subtype: string;
  is_deleted: boolean;
};
export type EntryRelations = {
  revision: number;
  items: RelatedEntry[];
  total_count: number;
};
export type RelationRequest = {
  entryID: string;
  mode: RelationMode;
  query: string;
  page: number;
};
export type RelationChange = {
  entryID: string;
  targetID: string;
  revision: number;
  linked: boolean;
};
export function validRelationRequest(input: RelationRequest) {
  return Boolean(
    input &&
    validHistoryID(input.entryID) &&
    relationModes.includes(input.mode) &&
    typeof input.query === "string" &&
    input.query.length <= 200 &&
    Number.isSafeInteger(input.page) &&
    input.page >= 0 &&
    input.page <= 5000,
  );
}
export function validRelationChange(input: RelationChange) {
  return Boolean(
    input &&
    validHistoryID(input.entryID) &&
    validHistoryID(input.targetID) &&
    input.entryID.toLowerCase() !== input.targetID.toLowerCase() &&
    Number.isSafeInteger(input.revision) &&
    input.revision > 0 &&
    typeof input.linked === "boolean",
  );
}
