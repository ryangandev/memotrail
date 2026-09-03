import "server-only";

import { cookies } from "next/headers";
import {
  homeTimezoneCookieName,
  localDateInTimezone,
  normalizeHomeTimezone,
} from "./home-input";
import { getAuthenticatedContext, type Viewer } from "./inbox";

export type HomeAttachment = {
  bucketId: string;
  byteSize: number | null;
  id: string;
  imageUrl: string | null;
  mimeType: string;
  objectPath: string;
  originalFilename: string | null;
  pixelHeight: number | null;
  pixelWidth: number | null;
};

export type HomeEntry = {
  attachments: HomeAttachment[];
  body: string;
  collectionNames: string[];
  createdAt: string;
  datePrecision: string;
  entryType: string;
  id: string;
  inboxStatus: "organized" | "unreviewed";
  occurredEnd: string | null;
  occurredLabel: string | null;
  occurredStart: string | null;
  occurredTimezone: string | null;
  revision: number;
  tagNames: string[];
  title: string;
  updatedAt: string;
};

export type HomeStage = {
  body: string;
  datePrecision: string;
  entryId: string;
  occurredEnd: string | null;
  occurredLabel: string | null;
  occurredStart: string;
  occurredTimezone: string | null;
  title: string;
  trackId: string;
  trackName: string;
};

export type HomeSnapshot = {
  activeHabitCount: number;
  collectionCount: number;
  completedHabitCount: number;
  currentStageCount: number;
  currentStages: HomeStage[];
  dueHabitCount: number;
  entryCount: number;
  firstTimeCount: number;
  inboxCount: number;
  profileDisplayName: string | null;
  recentEntries: HomeEntry[];
  skippedHabitCount: number;
  snapshotDate: string;
};

export type HomeWorkspace = {
  loadError: string | null;
  snapshot: HomeSnapshot | null;
  timezone: string;
  viewer: Viewer;
};

export async function getHomeWorkspace(): Promise<HomeWorkspace | null> {
  const context = await getAuthenticatedContext();

  if (!context) {
    return null;
  }

  const cookieStore = await cookies();
  const timezone = normalizeHomeTimezone(
    cookieStore.get(homeTimezoneCookieName)?.value,
  );
  const snapshotDate = localDateInTimezone(new Date(), timezone);
  const result = await context.client.rpc("home_workspace", {
    p_local_date: snapshotDate,
    p_recent_limit: 5,
    p_timezone: timezone,
  });
  const row = result.error ? null : parseHomeRow(result.data);

  if (!row) {
    return {
      loadError: "MemoTrail could not load Home. Refresh to try again.",
      snapshot: null,
      timezone,
      viewer: context.viewer,
    };
  }

  const attachments = row.recentEntries.flatMap((entry) => entry.attachments);
  const signedUrls = await signedImageUrls(context.client, attachments);

  return {
    loadError: null,
    snapshot: {
      ...row,
      recentEntries: row.recentEntries.map((entry) => ({
        ...entry,
        attachments: entry.attachments.map((attachment) => ({
          ...attachment,
          imageUrl: signedUrls.get(attachment.objectPath) ?? null,
        })),
      })),
    },
    timezone,
    viewer: context.viewer,
  };
}

function parseHomeRow(value: unknown): HomeSnapshot | null {
  if (!Array.isArray(value) || value.length !== 1 || !isRecord(value[0])) {
    return null;
  }

  const row = value[0];
  const recentEntries = parseRecentEntries(row.recent_entries);
  const currentStages = parseCurrentStages(row.current_stages);
  const counts = [
    row.active_habit_count,
    row.collection_count,
    row.completed_habit_count,
    row.current_stage_count,
    row.due_habit_count,
    row.entry_count,
    row.first_time_count,
    row.inbox_count,
    row.skipped_habit_count,
  ].map(safeCount);

  if (
    counts.some((count) => count === null) ||
    !recentEntries ||
    !currentStages ||
    typeof row.snapshot_date !== "string" ||
    !nullableString(row.profile_display_name)
  ) {
    return null;
  }

  return {
    activeHabitCount: counts[0]!,
    collectionCount: counts[1]!,
    completedHabitCount: counts[2]!,
    currentStageCount: counts[3]!,
    currentStages,
    dueHabitCount: counts[4]!,
    entryCount: counts[5]!,
    firstTimeCount: counts[6]!,
    inboxCount: counts[7]!,
    profileDisplayName: row.profile_display_name,
    recentEntries,
    skippedHabitCount: counts[8]!,
    snapshotDate: row.snapshot_date,
  };
}

function parseRecentEntries(value: unknown): HomeEntry[] | null {
  if (!Array.isArray(value)) {
    return null;
  }

  const entries: HomeEntry[] = [];

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
      typeof item.entry_type !== "string" ||
      (item.inbox_status !== "organized" &&
        item.inbox_status !== "unreviewed") ||
      !nullableString(item.occurred_start) ||
      !nullableString(item.occurred_end) ||
      typeof item.date_precision !== "string" ||
      !nullableString(item.occurred_label) ||
      !nullableString(item.occurred_timezone) ||
      typeof item.revision !== "number" ||
      typeof item.created_at !== "string" ||
      typeof item.updated_at !== "string" ||
      !stringArray(item.collection_names) ||
      !stringArray(item.tag_names)
    ) {
      return null;
    }

    entries.push({
      attachments,
      body: item.body,
      collectionNames: item.collection_names,
      createdAt: item.created_at,
      datePrecision: item.date_precision,
      entryType: item.entry_type,
      id: item.entry_id,
      inboxStatus: item.inbox_status,
      occurredEnd: item.occurred_end,
      occurredLabel: item.occurred_label,
      occurredStart: item.occurred_start,
      occurredTimezone: item.occurred_timezone,
      revision: item.revision,
      tagNames: item.tag_names,
      title: item.title,
      updatedAt: item.updated_at,
    });
  }

  return entries;
}

function parseAttachments(value: unknown): HomeAttachment[] | null {
  if (!Array.isArray(value)) {
    return null;
  }

  const attachments: HomeAttachment[] = [];

  for (const item of value) {
    if (
      !isRecord(item) ||
      typeof item.attachment_id !== "string" ||
      typeof item.bucket_id !== "string" ||
      typeof item.object_path !== "string" ||
      !nullableString(item.original_filename) ||
      typeof item.mime_type !== "string" ||
      !nullableNumber(item.byte_size) ||
      !nullableNumber(item.pixel_width) ||
      !nullableNumber(item.pixel_height)
    ) {
      return null;
    }

    attachments.push({
      bucketId: item.bucket_id,
      byteSize: item.byte_size,
      id: item.attachment_id,
      imageUrl: null,
      mimeType: item.mime_type,
      objectPath: item.object_path,
      originalFilename: item.original_filename,
      pixelHeight: item.pixel_height,
      pixelWidth: item.pixel_width,
    });
  }

  return attachments;
}

function parseCurrentStages(value: unknown): HomeStage[] | null {
  if (!Array.isArray(value)) {
    return null;
  }

  const stages: HomeStage[] = [];

  for (const item of value) {
    if (
      !isRecord(item) ||
      typeof item.entry_id !== "string" ||
      typeof item.title !== "string" ||
      typeof item.body !== "string" ||
      typeof item.track_id !== "string" ||
      typeof item.track_name !== "string" ||
      typeof item.occurred_start !== "string" ||
      !nullableString(item.occurred_end) ||
      typeof item.date_precision !== "string" ||
      !nullableString(item.occurred_label) ||
      !nullableString(item.occurred_timezone)
    ) {
      return null;
    }

    stages.push({
      body: item.body,
      datePrecision: item.date_precision,
      entryId: item.entry_id,
      occurredEnd: item.occurred_end,
      occurredLabel: item.occurred_label,
      occurredStart: item.occurred_start,
      occurredTimezone: item.occurred_timezone,
      title: item.title,
      trackId: item.track_id,
      trackName: item.track_name,
    });
  }

  return stages;
}

async function signedImageUrls(
  client: NonNullable<
    Awaited<ReturnType<typeof getAuthenticatedContext>>
  >["client"],
  attachments: HomeAttachment[],
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

function safeCount(value: unknown) {
  const count = typeof value === "string" ? Number(value) : value;
  return typeof count === "number" && Number.isSafeInteger(count) && count >= 0
    ? count
    : null;
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
