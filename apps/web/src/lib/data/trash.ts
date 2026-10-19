import "server-only";
import { displayImageURLs } from "@/lib/media/urls";

import { getAuthenticatedContext, type Viewer } from "./inbox";
import { TRASH_PAGE_SIZE, type TrashItemKind } from "./trash-input";
import { isWikiItemKind, type WikiItemKind } from "./wiki-item";
import { entryDisplayTitle, storedOccurrence } from "./occurrence";
import { storedProfileTimezone } from "./profile-input";
import { loadReviewSettings } from "./reviews";

export type TrashItem = {
  deletedAt: string;
  detail: string | null;
  expiresAt: string;
  id: string;
  imageUrl: string | null;
  kind: TrashItemKind;
  revision: number | null;
  title: string;
  wikiItemKind: WikiItemKind | null;
  wikiItemSubtype: string | null;
};

export type TrashWorkspace = {
  items: TrashItem[];
  loadError: string | null;
  page: number;
  /** When the page was rendered, so every date and countdown agrees on "now". */
  renderedAt: string;
  /** Whether reviews or Chapter suggestions exist, so deleting forever mentions them. */
  reviewsExist: boolean;
  /** The profile time zone Trash dates are shown in. */
  timezone: string;
  totalCount: number;
  viewer: Viewer;
};

// Each row carries its Entry's stored title and date: an Entry's own, or the
// Entry a photo belongs to.
type TrashRow = {
  date_precision: string;
  deleted_at: string;
  detail: string | null;
  entry_title: string;
  expires_at: string;
  item_id: string;
  item_kind: TrashItemKind;
  occurred_end: string | null;
  occurred_label: string | null;
  occurred_start: string | null;
  occurred_timezone: string | null;
  parent_entry_id: string | null;
  revision: number | null;
  storage_paths: string[];
  title: string;
  total_count: number | string;
  wiki_item_kind: WikiItemKind | null;
  wiki_item_subtype: string | null;
};

export async function getTrashWorkspace(
  page = 1,
): Promise<TrashWorkspace | null> {
  const context = await getAuthenticatedContext();

  if (!context) {
    return null;
  }

  const [trashResult, profile, reviewSettings] = await Promise.all([
    context.client.rpc("trash_workspace", {
      p_limit: TRASH_PAGE_SIZE,
      p_offset: (page - 1) * TRASH_PAGE_SIZE,
    }),
    context.client
      .from("profiles")
      .select("timezone")
      .eq("user_id", context.userId)
      .single(),
    loadReviewSettings(context.client),
  ]);
  const rows = trashResult.error ? null : parseTrashRows(trashResult.data);
  const imageUrls = rows
    ? await signedImageUrls(
        context.client,
        rows.flatMap((row) => row.storage_paths.slice(0, 1)),
      )
    : new Map<string, string>();

  return {
    items: (rows ?? []).map((row) => itemFromRow(row, imageUrls)),
    loadError:
      rows && !trashResult.error
        ? null
        : "MemoTrail could not load Trash. Refresh to try again.",
    page,
    renderedAt: new Date().toISOString(),
    reviewsExist:
      (reviewSettings?.reviewCount ?? 0) +
        (reviewSettings?.pendingSuggestionCount ?? 0) >
      0,
    timezone: storedProfileTimezone(profile.error ? null : profile.data)
      .timezone,
    totalCount: safeCount(rows?.[0]?.total_count ?? 0),
    viewer: context.viewer,
  };
}

function itemFromRow(row: TrashRow, imageUrls: Map<string, string>): TrashItem {
  const entryTitle = entryDisplayTitle(
    row.entry_title,
    storedOccurrence({
      datePrecision: row.date_precision,
      occurredEnd: row.occurred_end,
      occurredLabel: row.occurred_label,
      occurredStart: row.occurred_start,
      occurredTimezone: row.occurred_timezone,
    }),
  );
  const photo = row.item_kind === "attachment";
  return {
    deletedAt: row.deleted_at,
    detail: photo ? `Photo from ${entryTitle}` : row.detail,
    expiresAt: row.expires_at,
    id: row.item_id,
    imageUrl: imageUrls.get(row.storage_paths[0] ?? "") ?? null,
    kind: row.item_kind,
    revision: row.revision,
    title: photo ? row.title : entryTitle,
    wikiItemKind: row.wiki_item_kind,
    wikiItemSubtype: row.wiki_item_subtype,
  };
}

async function signedImageUrls(
  client: NonNullable<
    Awaited<ReturnType<typeof getAuthenticatedContext>>
  >["client"],
  objectPaths: string[],
) {
  const paths = [...new Set(objectPaths.filter(Boolean))];
  return displayImageURLs(client, paths, true);
}

function parseTrashRows(value: unknown): TrashRow[] | null {
  if (!Array.isArray(value)) {
    return null;
  }

  return value.every(isTrashRow) ? value : null;
}

function isTrashRow(value: unknown): value is TrashRow {
  if (!isRecord(value)) {
    return false;
  }

  return (
    (value.item_kind === "entry" || value.item_kind === "attachment") &&
    typeof value.item_id === "string" &&
    typeof value.title === "string" &&
    nullableString(value.detail) &&
    typeof value.entry_title === "string" &&
    typeof value.date_precision === "string" &&
    nullableString(value.occurred_start) &&
    nullableString(value.occurred_end) &&
    nullableString(value.occurred_label) &&
    nullableString(value.occurred_timezone) &&
    typeof value.deleted_at === "string" &&
    typeof value.expires_at === "string" &&
    nullableInteger(value.revision) &&
    (value.wiki_item_kind === null || isWikiItemKind(value.wiki_item_kind)) &&
    nullableString(value.wiki_item_subtype) &&
    nullableString(value.parent_entry_id) &&
    stringArray(value.storage_paths) &&
    countLike(value.total_count)
  );
}

function nullableInteger(value: unknown) {
  return (
    value === null || (typeof value === "number" && Number.isInteger(value))
  );
}

function nullableString(value: unknown) {
  return value === null || typeof value === "string";
}

function stringArray(value: unknown): value is string[] {
  return (
    Array.isArray(value) && value.every((item) => typeof item === "string")
  );
}

function countLike(value: unknown): value is number | string {
  return typeof value === "number" || typeof value === "string";
}

function safeCount(value: number | string) {
  const count = typeof value === "number" ? value : Number(value);
  return Number.isSafeInteger(count) && count >= 0 ? count : 0;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}
