import "server-only";

import { entryFromRow, getAuthenticatedContext } from "./inbox";
import type { CaptureExtractionSource } from "./capture-extraction-input";

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export async function getCaptureExtractionSource(
  id: string | null,
): Promise<CaptureExtractionSource | null> {
  if (!id || !uuidPattern.test(id)) return null;
  const context = await getAuthenticatedContext();
  if (!context) return null;

  const { data, error } = await context.client.rpc(
    "capture_extraction_source",
    { p_capture_id: id },
  );
  if (error || !isSourceRow(data)) return null;

  return entryFromRow(data, data.collection_names, data.tag_names);
}

function isSourceRow(value: unknown): value is Parameters<
  typeof entryFromRow
>[0] & {
  collection_names: string[];
  tag_names: string[];
} {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const row = value as Record<string, unknown>;
  return (
    typeof row.id === "string" &&
    typeof row.body === "string" &&
    typeof row.created_at === "string" &&
    typeof row.entry_type === "string" &&
    row.item_kind === "capture" &&
    row.item_subtype === "quick_capture" &&
    typeof row.revision === "number" &&
    Array.isArray(row.collection_names) &&
    row.collection_names.every((name) => typeof name === "string") &&
    Array.isArray(row.tag_names) &&
    row.tag_names.every((name) => typeof name === "string")
  );
}
