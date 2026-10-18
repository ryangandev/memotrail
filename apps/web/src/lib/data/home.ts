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
import { isWikiItemKind, type WikiItemKind } from "./wiki-item";
import { isTimelineLane, type TimelineLane } from "./milestone";

export type { HomeAttachment, HomeEntry } from "./home-entry";
export type { HomeResurfacedMemory } from "./home-resurfacing";

/** A Home, Vehicle, or Period that has started and has no end yet. */
export type HomeNowItem = {
  datePrecision: string;
  entryId: string;
  isFirstTime: boolean;
  itemKind: WikiItemKind;
  itemSubtype: string;
  lane: TimelineLane;
  occurredEnd: string | null;
  occurredLabel: string | null;
  occurredStart: string;
  occurredTimezone: string | null;
  /** The stored title, blank when the Entry has none. */
  title: string;
};

export type HomeSnapshot = {
  tagCount: number;
  entryCount: number;
  firstTimeCount: number;
  nowCount: number;
  nowItems: HomeNowItem[];
  profileDisplayName: string | null;
  recentEntries: HomeEntry[];
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
  const nowItems = parseNowItems(row.now_items);
  const counts = [
    row.now_count,
    row.entry_count,
    row.first_time_count,
    row.tag_count,
  ].map(safeCount);

  if (
    counts.some((count) => count === null) ||
    !recentEntries ||
    !nowItems ||
    typeof row.snapshot_date !== "string" ||
    !nullableString(row.profile_display_name)
  ) {
    return null;
  }

  return {
    entryCount: counts[1]!,
    firstTimeCount: counts[2]!,
    nowCount: counts[0]!,
    nowItems,
    profileDisplayName: row.profile_display_name,
    recentEntries,
    snapshotDate: row.snapshot_date,
    tagCount: counts[3]!,
  };
}

function parseNowItems(value: unknown): HomeNowItem[] | null {
  if (!Array.isArray(value)) {
    return null;
  }

  const items: HomeNowItem[] = [];

  for (const item of value) {
    if (
      !isRecord(item) ||
      typeof item.entry_id !== "string" ||
      typeof item.title !== "string" ||
      !isWikiItemKind(item.item_kind) ||
      typeof item.item_subtype !== "string" ||
      !isTimelineLane(item.lane) ||
      typeof item.is_first_time !== "boolean" ||
      typeof item.occurred_start !== "string" ||
      !nullableString(item.occurred_end) ||
      typeof item.date_precision !== "string" ||
      !nullableString(item.occurred_label) ||
      !nullableString(item.occurred_timezone)
    ) {
      return null;
    }

    items.push({
      datePrecision: item.date_precision,
      entryId: item.entry_id,
      isFirstTime: item.is_first_time,
      itemKind: item.item_kind,
      itemSubtype: item.item_subtype,
      lane: item.lane,
      occurredEnd: item.occurred_end,
      occurredLabel: item.occurred_label,
      occurredStart: item.occurred_start,
      occurredTimezone: item.occurred_timezone,
      title: item.title,
    });
  }

  return items;
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
