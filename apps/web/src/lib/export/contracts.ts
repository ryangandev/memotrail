export const EXPORT_COMPLETE = "MEMOTRAIL_EXPORT_V1_COMPLETE";
export const EXPORT_TAIL_BYTES = 22 + EXPORT_COMPLETE.length;
export type ExportSnapshot = {
  id: string;
  schema_version: number;
  captured_at: string;
  expires_at: string;
  row_count: number;
  json_bytes: number;
  datasets: Record<string, number>;
};
export type ExportAction = {
  action: "list" | "create" | "discard" | "download";
  id?: string;
};
export function isUUID(value: unknown): value is string {
  return (
    typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
      value,
    )
  );
}
export function parseExportAction(value: unknown): ExportAction | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const v = value as Record<string, unknown>;
  if (Object.keys(v).some((key) => !["action", "id"].includes(key)))
    return null;
  if (v.action === "list" && v.id === undefined) return { action: "list" };
  if (
    ["create", "discard", "download"].includes(String(v.action)) &&
    isUUID(v.id)
  )
    return { action: v.action as ExportAction["action"], id: v.id };
  return null;
}
export function exportFilename(snapshot: ExportSnapshot) {
  return `MemoTrail-${snapshot.captured_at.slice(0, 10)}-${snapshot.id.slice(0, 8)}.zip`;
}
// Completeness marker in the standard ZIP end-of-central-directory record.
// This detects interrupted transfers, not corruption of arbitrary ZIP entries.
export function hasCompleteExport(tail: Uint8Array) {
  if (tail.length < EXPORT_TAIL_BYTES) return false;
  const end = tail.slice(-EXPORT_TAIL_BYTES);
  return (
    end[0] === 0x50 &&
    end[1] === 0x4b &&
    end[2] === 0x05 &&
    end[3] === 0x06 &&
    end[20] === EXPORT_COMPLETE.length &&
    end[21] === 0 &&
    new TextDecoder().decode(end.slice(22)) === EXPORT_COMPLETE
  );
}
export function appendExportTail(
  tail: Uint8Array,
  chunk: Uint8Array,
): Uint8Array {
  if (chunk.length >= EXPORT_TAIL_BYTES) return chunk.slice(-EXPORT_TAIL_BYTES);
  const combined = new Uint8Array(tail.length + chunk.length);
  combined.set(tail);
  combined.set(chunk, tail.length);
  return combined.slice(-EXPORT_TAIL_BYTES);
}
export function csvCell(value: unknown) {
  let text =
    value == null
      ? ""
      : typeof value === "object"
        ? JSON.stringify(value)
        : String(value);
  // Derived spreadsheet views are safe to open; canonical JSON stays unchanged.
  if (typeof value === "string" && /^[\s\u0000-\u001f]*[=+\-@]/u.test(text))
    text = "'" + text;
  return `"${text.replaceAll('"', '""')}"`;
}
export function entryMarkdown(entry: Record<string, unknown>) {
  const fields = [
    "id",
    "title",
    "entry_type",
    "date_precision",
    "occurred_start",
    "occurred_end",
    "occurred_label",
    "occurred_timezone",
    "created_at",
    "updated_at",
    "deleted_at",
  ];
  const frontmatter = fields
    .filter((key) => key in entry)
    .map((key) => `${key}: ${JSON.stringify(entry[key])}`)
    .join("\n");
  return `---\n${frontmatter}\n---\n\n${typeof entry.body === "string" ? entry.body : ""}\n`;
}
export function mediaArchivePath(row: Record<string, unknown>) {
  if (
    !isUUID(row.attachment_id) ||
    !["original", "thumbnail", "display"].includes(String(row.variant))
  )
    throw new Error("Invalid media identity.");
  const suffix = String(row.object_path).split(".").at(-1) ?? "";
  const extension = /^[a-z0-9]{1,12}$/i.test(suffix)
    ? suffix.toLowerCase()
    : "bin";
  return `media/${row.attachment_id}-${row.variant}.${extension}`;
}
