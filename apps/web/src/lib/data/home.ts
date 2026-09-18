import "server-only";
import { displayImageURLs } from "@/lib/media/urls";

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
  collectionCount: number;
  currentStageCount: number;
  currentStages: HomeStage[];
  entryCount: number;
  firstTimeCount: number;
  inboxCount: number;
  profileDisplayName: string | null;
  recentEntries: HomeEntry[];
  snapshotDate: string;
};

export type HomeInboxPreview = {
  body: string;
  createdAt: string;
  id: string;
  title: string | null;
};

export type HomeWorkspace = {
  inboxPreview: HomeInboxPreview[];
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
  const [result, resurfacingResult, inboxPreviewResult] = await Promise.all([
    context.client.rpc("home_workspace", {
      p_local_date: snapshotDate,
      p_recent_limit: 5,
      p_timezone: timezone,
    }),
    context.client.rpc("home_resurfaced_memory", {
      p_local_date: snapshotDate,
      p_timezone: timezone,
    }),
    context.client
      .from("entries")
      .select("id,title,body,created_at")
      .eq("owner_id", context.userId)
      .eq("inbox_status", "unreviewed")
      .is("deleted_at", null)
      .order("created_at", { ascending: false })
      .order("id", { ascending: false })
      .limit(3)
      .returns<HomeInboxPreviewRow[]>(),
  ]);
  const row = result.error ? null : parseHomeRow(result.data);
  const resurfacedMemory = resurfacingResult.error
    ? null
    : parseHomeResurfacedMemory(resurfacingResult.data);

  if (!row) {
    return {
      inboxPreview: parseInboxPreview(inboxPreviewResult.data),
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
    inboxPreview: parseInboxPreview(inboxPreviewResult.data),
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

type HomeInboxPreviewRow = {
  body: string;
  created_at: string;
  id: string;
  title: string | null;
};

function parseInboxPreview(rows: HomeInboxPreviewRow[] | null) {
  return (rows ?? []).map((row) => ({
    body: row.body,
    createdAt: row.created_at,
    id: row.id,
    title: row.title,
  }));
}

function parseHomeRow(value: unknown): HomeSnapshot | null {
  if (!Array.isArray(value) || value.length !== 1 || !isRecord(value[0])) {
    return null;
  }

  const row = value[0];
  const recentEntries = parseHomeEntries(row.recent_entries);
  const currentStages = parseCurrentStages(row.current_stages);
  const counts = [
    row.collection_count,
    row.current_stage_count,
    row.entry_count,
    row.first_time_count,
    row.inbox_count,
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
    collectionCount: counts[0]!,
    currentStageCount: counts[1]!,
    currentStages,
    entryCount: counts[2]!,
    firstTimeCount: counts[3]!,
    inboxCount: counts[4]!,
    profileDisplayName: row.profile_display_name,
    recentEntries,
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
  return displayImageURLs(client, paths);
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
