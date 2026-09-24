import "server-only";
import { displayImageURLs } from "@/lib/media/urls";

import {
  getAuthenticatedContext,
  loadEntryRichTextMap,
  type Viewer,
} from "./inbox";
import type { EntryRichText } from "./rich-text";
import { COLLECTION_PAGE_SIZE } from "./collections-input";
import { parseOrganizationItems, type OrganizationItem } from "./organization";
import { normalizeCounts } from "./organization-workspace";
import { isWikiItemKind, type WikiItemKind } from "./wiki-item";

export type CollectionSummary = {
  color: string | null;
  createdAt: string;
  entryCount: number;
  id: string;
  latestEntryAt: string | null;
  name: string;
  sortOrder: number;
  systemKey: string | null;
  unreviewedCount: number;
  updatedAt: string;
};

export type CollectionAttachment = {
  bucketId: string;
  byteSize: number | null;
  createdAt: string;
  id: string;
  imageUrl: string | null;
  mimeType: string;
  objectPath: string;
  originalFilename: string | null;
  parentAttachmentId: string | null;
  pixelHeight: number | null;
  pixelWidth: number | null;
  variant: "display" | "original" | "thumbnail";
};

export type CollectionEntry = {
  attachments: CollectionAttachment[];
  body: string;
  bodyRich: EntryRichText | null;
  collectionNames: string[];
  createdAt: string;
  datePrecision: string;
  id: string;
  inboxStatus: "organized" | "unreviewed";
  itemKind: WikiItemKind;
  itemSubtype: string;
  occurredEnd: string | null;
  occurredLabel: string | null;
  occurredStart: string | null;
  occurredTimezone: string | null;
  revision: number;
  recordId: string;
  recordSource: "entry" | "person";
  tagNames: string[];
  title: string | null;
  updatedAt: string;
};

export type CollectionsWorkspace = {
  collections: CollectionSummary[];
  detailLoadError: string | null;
  entries: CollectionEntry[];
  inboxCount: number | undefined;
  loadError: string | null;
  organizationItems: OrganizationItem[];
  page: number;
  selectedCollection: CollectionSummary | null;
  totalCount: number;
  viewer: Viewer;
};

type CollectionSummaryRow = {
  collection_id: string;
  color: string | null;
  created_at: string;
  entry_count: number | string;
  latest_entry_at: string | null;
  name: string;
  sort_order: number;
  system_key: string | null;
  unreviewed_count: number | string;
  updated_at: string;
};

type CollectionEntryRow = {
  attachments: unknown;
  body: string;
  collection_id: string;
  collection_name: string;
  collection_names: string[];
  created_at: string;
  date_precision: string;
  entry_id: string;
  inbox_status: "organized" | "unreviewed";
  item_kind: WikiItemKind;
  item_subtype: string;
  occurred_end: string | null;
  occurred_label: string | null;
  occurred_start: string | null;
  occurred_timezone: string | null;
  revision: number;
  record_id: string;
  record_source: "entry" | "person";
  tag_names: string[];
  title: string | null;
  total_count: number | string;
  updated_at: string;
};

export async function getCollectionsWorkspace({
  collectionId = null,
  page = 1,
}: {
  collectionId?: string | null;
  page?: number;
} = {}): Promise<CollectionsWorkspace | null> {
  const context = await getAuthenticatedContext();

  if (!context) {
    return null;
  }

  const detailRequest = collectionId
    ? context.client.rpc("collection_wiki_items", {
        p_collection_id: collectionId,
        p_limit: COLLECTION_PAGE_SIZE,
        p_offset: (page - 1) * COLLECTION_PAGE_SIZE,
      })
    : Promise.resolve({ data: [] as CollectionEntryRow[], error: null });
  const [summaryResult, detailResult, inboxResult, organizationResult] =
    await Promise.all([
      context.client.rpc("collections_workspace"),
      detailRequest,
      context.client
        .from("entries")
        .select("id", { count: "exact", head: true })
        .eq("owner_id", context.userId)
        .eq("inbox_status", "unreviewed")
        .is("deleted_at", null),
      context.client.rpc("organization_workspace", {
        p_kind: "collection",
        p_limit: 100,
        p_offset: 0,
        p_query: "",
      }),
    ]);
  const summaryRows = summaryResult.error
    ? null
    : parseCollectionSummaryRows(summaryResult.data);
  const detailRows = detailResult.error
    ? null
    : parseCollectionEntryRows(detailResult.data);
  const collections = (summaryRows ?? []).map(summaryFromRow);
  const parsedEntries = detailRows ?? [];
  const [signedUrls, bodyRichByEntry] = await Promise.all([
    signedImageUrls(
      context.client,
      parsedEntries.flatMap((row) => parseAttachments(row.attachments) ?? []),
    ),
    loadEntryRichTextMap(
      context,
      parsedEntries.map((row) => ({ body: row.body, id: row.entry_id })),
    ),
  ]);

  return {
    collections,
    detailLoadError:
      collectionId && (!detailRows || detailResult.error)
        ? "MemoTrail could not load this Collection. Refresh to try again."
        : null,
    entries: parsedEntries.map((row) =>
      entryFromRow(row, signedUrls, bodyRichByEntry.get(row.entry_id)),
    ),
    inboxCount: inboxResult.error ? undefined : (inboxResult.count ?? 0),
    loadError:
      summaryRows && !summaryResult.error
        ? null
        : "MemoTrail could not load your Collections. Refresh to try again.",
    organizationItems: (
      parseOrganizationItems(organizationResult.data) ?? []
    ).map(normalizeCounts),
    page,
    selectedCollection:
      collections.find((collection) => collection.id === collectionId) ?? null,
    totalCount: countFromRows(parsedEntries),
    viewer: context.viewer,
  };
}

function summaryFromRow(row: CollectionSummaryRow): CollectionSummary {
  return {
    color: row.color,
    createdAt: row.created_at,
    entryCount: safeCount(row.entry_count),
    id: row.collection_id,
    latestEntryAt: row.latest_entry_at,
    name: row.name,
    sortOrder: row.sort_order,
    systemKey: row.system_key,
    unreviewedCount: safeCount(row.unreviewed_count),
    updatedAt: row.updated_at,
  };
}

function entryFromRow(
  row: CollectionEntryRow,
  signedUrls: Map<string, string>,
  bodyRich: EntryRichText | null = null,
): CollectionEntry {
  return {
    attachments: (parseAttachments(row.attachments) ?? []).map(
      (attachment) => ({
        ...attachment,
        imageUrl: signedUrls.get(attachment.objectPath) ?? null,
      }),
    ),
    body: row.body,
    bodyRich,
    collectionNames: row.collection_names,
    createdAt: row.created_at,
    datePrecision: row.date_precision,
    id: row.entry_id,
    inboxStatus: row.inbox_status,
    itemKind: row.item_kind,
    itemSubtype: row.item_subtype,
    occurredEnd: row.occurred_end,
    occurredLabel: row.occurred_label,
    occurredStart: row.occurred_start,
    occurredTimezone: row.occurred_timezone,
    revision: row.revision,
    recordId: row.record_id,
    recordSource: row.record_source,
    tagNames: row.tag_names,
    title: row.title,
    updatedAt: row.updated_at,
  };
}

async function signedImageUrls(
  client: NonNullable<
    Awaited<ReturnType<typeof getAuthenticatedContext>>
  >["client"],
  attachments: CollectionAttachment[],
) {
  const paths = [...new Set(attachments.map((item) => item.objectPath))];
  return displayImageURLs(client, paths);
}

function parseCollectionSummaryRows(
  value: unknown,
): CollectionSummaryRow[] | null {
  if (!Array.isArray(value)) {
    return null;
  }

  return value.every(isCollectionSummaryRow) ? value : null;
}

function isCollectionSummaryRow(value: unknown): value is CollectionSummaryRow {
  if (!isRecord(value)) {
    return false;
  }

  return (
    typeof value.collection_id === "string" &&
    typeof value.name === "string" &&
    nullableString(value.system_key) &&
    nullableString(value.color) &&
    typeof value.sort_order === "number" &&
    countLike(value.entry_count) &&
    countLike(value.unreviewed_count) &&
    nullableString(value.latest_entry_at) &&
    typeof value.created_at === "string" &&
    typeof value.updated_at === "string"
  );
}

function parseCollectionEntryRows(value: unknown): CollectionEntryRow[] | null {
  if (!Array.isArray(value)) {
    return null;
  }

  return value.every(isCollectionEntryRow) ? value : null;
}

function isCollectionEntryRow(value: unknown): value is CollectionEntryRow {
  if (!isRecord(value)) {
    return false;
  }

  return (
    typeof value.collection_id === "string" &&
    typeof value.collection_name === "string" &&
    countLike(value.total_count) &&
    typeof value.entry_id === "string" &&
    nullableString(value.title) &&
    typeof value.body === "string" &&
    isWikiItemKind(value.item_kind) &&
    typeof value.item_subtype === "string" &&
    (value.inbox_status === "organized" ||
      value.inbox_status === "unreviewed") &&
    nullableString(value.occurred_start) &&
    nullableString(value.occurred_end) &&
    typeof value.date_precision === "string" &&
    nullableString(value.occurred_label) &&
    nullableString(value.occurred_timezone) &&
    typeof value.revision === "number" &&
    typeof value.record_id === "string" &&
    ["entry", "person"].includes(String(value.record_source)) &&
    typeof value.created_at === "string" &&
    typeof value.updated_at === "string" &&
    stringArray(value.collection_names) &&
    stringArray(value.tag_names) &&
    parseAttachments(value.attachments) !== null
  );
}

function parseAttachments(value: unknown): CollectionAttachment[] | null {
  if (!Array.isArray(value)) {
    return null;
  }

  const attachments: CollectionAttachment[] = [];

  for (const item of value) {
    if (
      !isRecord(item) ||
      typeof item.id !== "string" ||
      !nullableString(item.parentAttachmentId) ||
      (item.variant !== "original" &&
        item.variant !== "display" &&
        item.variant !== "thumbnail") ||
      typeof item.bucketId !== "string" ||
      typeof item.objectPath !== "string" ||
      !nullableString(item.originalFilename) ||
      typeof item.mimeType !== "string" ||
      !nullableNumber(item.byteSize) ||
      !nullableNumber(item.pixelWidth) ||
      !nullableNumber(item.pixelHeight) ||
      typeof item.createdAt !== "string"
    ) {
      return null;
    }

    attachments.push({
      bucketId: item.bucketId,
      byteSize: item.byteSize,
      createdAt: item.createdAt,
      id: item.id,
      imageUrl: null,
      mimeType: item.mimeType,
      objectPath: item.objectPath,
      originalFilename: item.originalFilename,
      parentAttachmentId: item.parentAttachmentId,
      pixelHeight: item.pixelHeight,
      pixelWidth: item.pixelWidth,
      variant: item.variant,
    });
  }

  return attachments;
}

function countFromRows(rows: CollectionEntryRow[]) {
  return safeCount(rows[0]?.total_count ?? 0);
}

function safeCount(value: number | string) {
  const count = typeof value === "number" ? value : Number(value);
  return Number.isSafeInteger(count) && count >= 0 ? count : 0;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function nullableString(value: unknown): value is string | null {
  return value === null || typeof value === "string";
}

function nullableNumber(value: unknown): value is number | null {
  return value === null || typeof value === "number";
}

function stringArray(value: unknown): value is string[] {
  return (
    Array.isArray(value) && value.every((item) => typeof item === "string")
  );
}

function countLike(value: unknown): value is number | string {
  return typeof value === "number" || typeof value === "string";
}
