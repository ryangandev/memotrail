import { expect, it } from "vitest";
import {
  relationModeLabels,
  validRelationRequest,
  validRelationChange,
  type RelationRequest,
  type RelationChange,
} from "./entry-relations";
const entryID = "93800000-0000-4000-8000-000000000001",
  targetID = "93800000-0000-4000-8000-000000000002";
const read: RelationRequest = {
  entryID,
  mode: "incoming",
  query: "牙套",
  page: 0,
};
const change: RelationChange = { entryID, targetID, revision: 2, linked: true };
it("supports outgoing links, backlinks, and paginated candidates", () => {
  expect(validRelationRequest(read)).toBe(true);
  expect(Object.values(relationModeLabels)).toEqual([
    "Linked Items",
    "Linked from",
    "Find Items",
  ]);
  expect(validRelationRequest({ ...read, page: 5000 })).toBe(true);
});
it.each([-1, 5001, 1.5, NaN, Infinity])(
  "rejects invalid relationship page %s",
  (page) => {
    expect(validRelationRequest({ ...read, page })).toBe(false);
  },
);
it("rejects oversized searches, malformed ids, and unsupported views", () => {
  expect(validRelationRequest({ ...read, query: "x".repeat(201) })).toBe(false);
  expect(validRelationRequest({ ...read, entryID: "other" })).toBe(false);
  expect(
    validRelationRequest({
      ...read,
      mode: "delete",
    } as unknown as RelationRequest),
  ).toBe(false);
});
it("validates revisioned link and unlink requests", () => {
  expect(validRelationChange(change)).toBe(true);
  expect(validRelationChange({ ...change, linked: false })).toBe(true);
  expect(
    validRelationChange({ ...change, targetID: entryID.toUpperCase() }),
  ).toBe(false);
  expect(validRelationChange({ ...change, revision: 0 })).toBe(false);
  expect(
    validRelationChange({
      ...change,
      linked: "false",
    } as unknown as RelationChange),
  ).toBe(false);
});
