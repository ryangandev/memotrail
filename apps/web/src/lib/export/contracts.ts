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
  // UUIDs are case-insensitive; snapshots are compared in Postgres' lowercase form.
  if (
    ["create", "discard", "download"].includes(String(v.action)) &&
    isUUID(v.id)
  )
    return {
      action: v.action as ExportAction["action"],
      id: v.id.toLowerCase(),
    };
  return null;
}
export function exportFilename(
  snapshot: Pick<ExportSnapshot, "captured_at" | "id">,
) {
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
// The readable Entries table leaves out the writing, which entries/*.md already holds. A Chapter
// is an Entry whose item_subtype is chapter, and a First Time is an Entry marked is_first_time.
export const ENTRY_TABLE_COLUMNS = [
  "id",
  "title",
  "item_subtype",
  "is_first_time",
  "date_precision",
  "occurred_start",
  "occurred_end",
  "occurred_label",
  "occurred_timezone",
  "created_at",
  "updated_at",
  "deleted_at",
] as const;
export function entryTableHeader() {
  return ENTRY_TABLE_COLUMNS.map(csvCell).join(",") + "\r\n";
}
export function entryTableLine(entry: Record<string, unknown>) {
  return (
    ENTRY_TABLE_COLUMNS.map((key) => csvCell(entry[key])).join(",") + "\r\n"
  );
}
export function entryMarkdown(entry: Record<string, unknown>) {
  const fields = [
    "id",
    "title",
    "item_kind",
    "item_subtype",
    "is_first_time",
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
const isObject = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const quoted = (text: string) =>
  text
    .split("\n")
    .map((line) => (line ? `> ${line}` : ">"))
    .join("\n");

const stringList = (value: unknown) =>
  Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string")
    : [];

/** The last day before an exclusive end, as YYYY-MM-DD, or the start when the end is unusable. */
function lastDay(start: string, endExclusive: string) {
  const end = Date.parse(`${endExclusive}T00:00:00Z`);
  const first = Date.parse(`${start}T00:00:00Z`);
  if (!Number.isFinite(end) || !Number.isFinite(first)) return start;
  return new Date(Math.max(first, end - 86_400_000)).toISOString().slice(0, 10);
}

const fromEntries = (ids: string[]) =>
  ids.length
    ? `From ${ids.map((entryId) => `entries/${entryId}.md`).join(", ")}`
    : null;

/**
 * A stored review as readable Markdown, or null when the row has no review. It is a record of
 * what was stored, so quotes are the stored text and are not checked against the Entries again.
 * `chapterTitle` names a Chapter review.
 */
export function reviewMarkdown(
  review: Record<string, unknown>,
  chapterTitle: string | null,
) {
  const content = review.content;
  if (!isObject(content) || typeof content.summary !== "string") return null;
  const fields = [
    "id",
    "scope",
    "chapter_id",
    "review_year",
    "model",
    "generated_at",
    "entries_read",
    "entries_in_period",
  ];
  const frontmatter = fields
    .map((key) => `${key}: ${JSON.stringify(review[key] ?? null)}`)
    .join("\n");
  const subject =
    review.scope === "year"
      ? String(review.review_year ?? "")
      : chapterTitle?.trim() || "this Chapter";
  const feelings = isObject(content.feelings) ? content.feelings : {};
  const phases = Array.isArray(feelings.phases) ? feelings.phases : [];
  const themes = Array.isArray(content.themes) ? content.themes : [];
  const quotes = Array.isArray(content.quotes) ? content.quotes : [];

  const parts = [
    `---\n${frontmatter}\n---`,
    `# Review of ${subject}`,
    "> Written by Claude at your request. This is AI interpretation, not your own writing. Quotes are copied exactly from your Entries.",
    content.summary,
  ];

  const felt: string[] = [];
  if (typeof feelings.overview === "string" && feelings.overview)
    felt.push(feelings.overview);
  for (const phase of phases) {
    if (!isObject(phase) || typeof phase.feeling !== "string") continue;
    const start =
      typeof phase.windowStart === "string" ? phase.windowStart : "";
    const end = typeof phase.windowEnd === "string" ? phase.windowEnd : "";
    const dates = start
      ? end
        ? `${start} to ${lastDay(start, end)}`
        : start
      : null;
    felt.push(
      [
        `### ${phase.feeling}`,
        dates ? `Entries dated ${dates}.` : null,
        typeof phase.description === "string" ? phase.description : null,
        fromEntries(stringList(phase.entryIds)),
      ]
        .filter(Boolean)
        .join("\n\n"),
    );
  }
  if (felt.length) parts.push(["## How it felt", ...felt].join("\n\n"));

  const themeParts: string[] = [];
  for (const theme of themes) {
    if (!isObject(theme) || typeof theme.name !== "string") continue;
    themeParts.push(
      [
        `### ${theme.name}`,
        typeof theme.description === "string" ? theme.description : null,
        fromEntries(stringList(theme.entryIds)),
      ]
        .filter(Boolean)
        .join("\n\n"),
    );
  }
  if (themeParts.length)
    parts.push(["## What kept coming back", ...themeParts].join("\n\n"));

  const quoteParts: string[] = [];
  for (const quote of quotes) {
    if (!isObject(quote) || typeof quote.text !== "string") continue;
    quoteParts.push(
      [
        quoted(quote.text),
        ">",
        `> From entries/${typeof quote.entryId === "string" ? quote.entryId : ""}.md`,
        typeof quote.why === "string" && quote.why
          ? `\nWhy it stands out: ${quote.why}`
          : "",
      ].join("\n"),
    );
  }
  if (quoteParts.length)
    parts.push(["## In your words", ...quoteParts].join("\n\n"));
  return `${parts.join("\n\n")}\n`;
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
