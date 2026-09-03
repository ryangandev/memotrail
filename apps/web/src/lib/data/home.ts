import "server-only";

import { cookies } from "next/headers";
import {
  homeTimezoneCookieName,
  localDateInTimezone,
  normalizeHomeTimezone,
} from "./home-input";
import {
  parseHomeEntries,
  type HomeAttachment,
  type HomeEntry,
} from "./home-entry";
import {
  parseHomeResurfacedMemory,
  type HomeResurfacedMemory,
} from "./home-resurfacing";
import { getAuthenticatedContext, type Viewer } from "./inbox";

export type { HomeAttachment, HomeEntry } from "./home-entry";
export type { HomeResurfacedMemory } from "./home-resurfacing";

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
  resurfacedMemory: HomeResurfacedMemory | null;
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
  const [result, resurfacingResult] = await Promise.all([
    context.client.rpc("home_workspace", {
      p_local_date: snapshotDate,
      p_recent_limit: 5,
      p_timezone: timezone,
    }),
    context.client.rpc("home_resurfaced_memory", {
      p_local_date: snapshotDate,
      p_timezone: timezone,
    }),
  ]);
  const row = result.error ? null : parseHomeRow(result.data);
  const resurfacedMemory = resurfacingResult.error
    ? null
    : parseHomeResurfacedMemory(resurfacingResult.data);

  if (!row) {
    return {
      loadError: "MemoTrail could not load Home. Refresh to try again.",
      resurfacedMemory: null,
      snapshot: null,
      timezone,
      viewer: context.viewer,
    };
  }

  const attachments = [
    ...row.recentEntries.flatMap((entry) => entry.attachments),
    ...(resurfacedMemory?.attachments ?? []),
  ];
  const signedUrls = await signedImageUrls(context.client, attachments);

  return {
    loadError: null,
    resurfacedMemory: resurfacedMemory
      ? withSignedImageUrls(resurfacedMemory, signedUrls)
      : null,
    snapshot: {
      ...row,
      recentEntries: row.recentEntries.map((entry) =>
        withSignedImageUrls(entry, signedUrls),
      ),
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
  const recentEntries = parseHomeEntries(row.recent_entries);
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

function withSignedImageUrls<T extends HomeEntry>(
  entry: T,
  signedUrls: Map<string, string>,
): T {
  return {
    ...entry,
    attachments: entry.attachments.map((attachment) => ({
      ...attachment,
      imageUrl: signedUrls.get(attachment.objectPath) ?? null,
    })),
  };
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
