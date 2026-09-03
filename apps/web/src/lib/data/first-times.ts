import "server-only";

import { getAuthenticatedContext, type Viewer } from "./inbox";
import {
  firstTimeDatePrecisions,
  firstTimeImageMimeTypes,
  type FirstTimeDatePrecision,
  type FirstTimeImageMimeType,
} from "./first-time-input";

export type FirstTimeAttachment = {
  bucketId: string;
  byteSize: number;
  createdAt: string;
  id: string;
  imageUrl: string | null;
  mimeType: FirstTimeImageMimeType;
  objectPath: string;
  originalFilename: string | null;
  parentAttachmentId: string | null;
  pixelHeight: number | null;
  pixelWidth: number | null;
  variant: "display" | "original" | "thumbnail";
};

export type FirstTimeEntry = {
  attachments: FirstTimeAttachment[];
  body: string;
  collectionNames: string[];
  datePrecision: FirstTimeDatePrecision;
  id: string;
  inboxStatus: "organized" | "unreviewed";
  occurredLabel: string | null;
  occurredStart: string | null;
  occurredTimezone: string | null;
  revision: number;
  tagNames: string[];
  title: string;
  updatedAt: string;
};

export type FirstTimesWorkspace = {
  collectionOptions: string[];
  entries: FirstTimeEntry[];
  inboxCount: number | undefined;
  loadError: string | null;
  tagOptions: string[];
  viewer: Viewer;
};

type FirstTimeRow = {
  attachments: unknown;
  body: string;
  collection_names: string[];
  date_precision: FirstTimeDatePrecision;
  entry_id: string;
  inbox_status: "organized" | "unreviewed";
  occurred_label: string | null;
  occurred_start: string | null;
  occurred_timezone: string | null;
  revision: number;
  tag_names: string[];
  title: string;
  updated_at: string;
};

type NameRow = { name: string };

export async function getFirstTimesWorkspace(): Promise<FirstTimesWorkspace | null> {
  const context = await getAuthenticatedContext();

  if (!context) {
    return null;
  }

  const [firstTimes, collections, tags, inbox] = await Promise.all([
    context.client.rpc("first_times_workspace"),
    context.client
      .from("collections")
      .select("name")
      .eq("owner_id", context.userId)
      .is("archived_at", null)
      .order("name")
      .returns<NameRow[]>(),
    context.client
      .from("tags")
      .select("name")
      .eq("owner_id", context.userId)
      .order("name")
      .returns<NameRow[]>(),
    context.client
      .from("entries")
      .select("id", { count: "exact", head: true })
      .eq("owner_id", context.userId)
      .eq("inbox_status", "unreviewed")
      .is("deleted_at", null),
  ]);
  const rows = firstTimes.error ? null : parseFirstTimeRows(firstTimes.data);

  if (!rows) {
    return unavailableWorkspace(context.viewer, inbox.count ?? undefined);
  }

  const attachments = rows.flatMap((row) => row.attachments);
  const signedUrls = await signedImageUrls(context.client, attachments);

  return {
    collectionOptions: collections.error
      ? []
      : (collections.data ?? []).map((item) => item.name),
    entries: rows.map((row) => ({
      attachments: row.attachments.map((attachment) => ({
        ...attachment,
        imageUrl: signedUrls.get(attachment.objectPath) ?? null,
      })),
      body: row.body,
      collectionNames: row.collection_names,
      datePrecision: row.date_precision,
      id: row.entry_id,
      inboxStatus: row.inbox_status,
      occurredLabel: row.occurred_label,
      occurredStart: row.occurred_start,
      occurredTimezone: row.occurred_timezone,
      revision: row.revision,
      tagNames: row.tag_names,
      title: row.title,
      updatedAt: row.updated_at,
    })),
    inboxCount: inbox.error ? undefined : (inbox.count ?? 0),
    loadError: null,
    tagOptions: tags.error ? [] : (tags.data ?? []).map((item) => item.name),
    viewer: context.viewer,
  };
}

async function signedImageUrls(
  client: NonNullable<
    Awaited<ReturnType<typeof getAuthenticatedContext>>
  >["client"],
  attachments: FirstTimeAttachment[],
) {
  const paths = [...new Set(attachments.map((item) => item.objectPath))];
  const urls = new Map<string, string>();

  if (paths.length === 0) {
    return urls;
  }

  const { data, error } = await client.storage
    .from("entry-media")
    .createSignedUrls(paths, 60 * 60);

  if (error) {
    return urls;
  }

  for (const item of data ?? []) {
    if (item.path && item.signedUrl) {
      urls.set(item.path, item.signedUrl);
    }
  }

  return urls;
}

function parseFirstTimeRows(value: unknown):
  | (FirstTimeRow & {
      attachments: FirstTimeAttachment[];
    })[]
  | null {
  if (!Array.isArray(value)) {
    return null;
  }

  const rows: (FirstTimeRow & { attachments: FirstTimeAttachment[] })[] = [];

  for (const item of value) {
    if (!isRecord(item)) {
      return null;
    }

    const attachments = parseAttachments(item.attachments);

    if (
      !attachments ||
      typeof item.entry_id !== "string" ||
      typeof item.title !== "string" ||
      typeof item.body !== "string" ||
      (item.inbox_status !== "organized" &&
        item.inbox_status !== "unreviewed") ||
      typeof item.date_precision !== "string" ||
      !firstTimeDatePrecisions.includes(
        item.date_precision as FirstTimeDatePrecision,
      ) ||
      !nullableString(item.occurred_start) ||
      !nullableString(item.occurred_label) ||
      !nullableString(item.occurred_timezone) ||
      typeof item.revision !== "number" ||
      typeof item.updated_at !== "string" ||
      !stringArray(item.collection_names) ||
      !stringArray(item.tag_names)
    ) {
      return null;
    }

    rows.push({
      attachments,
      body: item.body,
      collection_names: item.collection_names,
      date_precision: item.date_precision as FirstTimeDatePrecision,
      entry_id: item.entry_id,
      inbox_status: item.inbox_status,
      occurred_label: item.occurred_label,
      occurred_start: item.occurred_start,
      occurred_timezone: item.occurred_timezone,
      revision: item.revision,
      tag_names: item.tag_names,
      title: item.title,
      updated_at: item.updated_at,
    });
  }

  return rows;
}

function parseAttachments(value: unknown): FirstTimeAttachment[] | null {
  if (!Array.isArray(value)) {
    return null;
  }

  const attachments: FirstTimeAttachment[] = [];

  for (const item of value) {
    if (
      !isRecord(item) ||
      typeof item.id !== "string" ||
      typeof item.bucketId !== "string" ||
      typeof item.objectPath !== "string" ||
      typeof item.mimeType !== "string" ||
      !firstTimeImageMimeTypes.includes(
        item.mimeType as FirstTimeImageMimeType,
      ) ||
      typeof item.byteSize !== "number" ||
      typeof item.createdAt !== "string" ||
      !nullableString(item.parentAttachmentId) ||
      !nullableString(item.originalFilename) ||
      !nullableNumber(item.pixelWidth) ||
      !nullableNumber(item.pixelHeight) ||
      (item.variant !== "original" &&
        item.variant !== "display" &&
        item.variant !== "thumbnail")
    ) {
      return null;
    }

    attachments.push({
      bucketId: item.bucketId,
      byteSize: item.byteSize,
      createdAt: item.createdAt,
      id: item.id,
      imageUrl: null,
      mimeType: item.mimeType as FirstTimeImageMimeType,
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

function unavailableWorkspace(
  viewer: Viewer,
  inboxCount: number | undefined,
): FirstTimesWorkspace {
  return {
    collectionOptions: [],
    entries: [],
    inboxCount,
    loadError:
      "MemoTrail could not load your First Times. Refresh to try again.",
    tagOptions: [],
    viewer,
  };
}

function stringArray(value: unknown): value is string[] {
  return (
    Array.isArray(value) && value.every((item) => typeof item === "string")
  );
}

function nullableNumber(value: unknown): value is number | null {
  return value === null || typeof value === "number";
}

function nullableString(value: unknown): value is string | null {
  return value === null || typeof value === "string";
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}
