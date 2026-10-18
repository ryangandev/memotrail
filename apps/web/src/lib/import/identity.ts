import { createHash } from "node:crypto";
import type { ImportCandidate, ImportSource } from "./types";

/** Fixed for good: changing it would give every imported Entry a new ID. */
export const importNamespace = "6c0f2a9e-3b1d-4f7a-9d52-8e1a4c7b5d30";

/** A version 5 UUID: the same name in the same namespace always gives the same ID. */
export function uuidV5(name: string, namespace: string): string {
  const bytes = createHash("sha1")
    .update(Buffer.from(namespace.replaceAll("-", ""), "hex"))
    .update(name, "utf8")
    .digest()
    .subarray(0, 16);
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.toString("hex");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

/**
 * An imported Entry's ID is fixed by who imported it and which item it is, so a retry, a
 * double click, and two open tabs all arrive at the same Entry.
 */
export function importEntryId(
  ownerId: string,
  source: ImportSource,
  sourceKey: string,
) {
  return uuidV5(`${ownerId}|${source}|${sourceKey}`, importNamespace);
}

export function importAttachmentId(entryId: string, resourceKey: string) {
  return uuidV5(`${entryId}|${resourceKey}`, importNamespace);
}

export function sha256Hex(value: string) {
  return createHash("sha256").update(value, "utf8").digest("hex");
}

/** JSON with sorted keys, so equal values always give equal text. */
export function canonicalJson(value: unknown): string {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  const record = value as Record<string, unknown>;
  return `{${Object.keys(record)
    .filter((key) => record[key] !== undefined)
    .sort()
    .map((key) => `${JSON.stringify(key)}:${canonicalJson(record[key])}`)
    .join(",")}}`;
}

/**
 * Hashes what an import would write, so a second import can tell an unchanged item from one
 * edited in the source. It leaves out anything that changes between exports of the same
 * item: file times, warnings, the folder it sits in, and how the zip happened to be laid out.
 */
export function candidateContentHash(
  candidate: Pick<
    ImportCandidate,
    | "title"
    | "date"
    | "tagNames"
    | "propertyTagNames"
    | "locationLabel"
  > & { plainText: string; photoNames: string[] },
) {
  return sha256Hex(
    canonicalJson({
      title: candidate.title ?? "",
      text: normalizeForHash(candidate.plainText),
      date: candidate.date,
      tags: [...candidate.tagNames, ...candidate.propertyTagNames]
        .map((name) => name.trim().toLocaleLowerCase())
        .sort(),
      location: candidate.locationLabel ?? "",
      photos: [...candidate.photoNames].sort(),
    }),
  );
}

function normalizeForHash(text: string) {
  return text.replace(/\s+/g, " ").trim();
}
