import "server-only";

import { getAuthenticatedContext, type Viewer } from "@/lib/data/inbox";
import type {
  TimelineDatePrecision,
  TimelineKind,
} from "@/lib/data/timeline-input";

export type TimelineEntry = {
  body: string;
  datePrecision: TimelineDatePrecision;
  entryType: string;
  id: string;
  kind: TimelineKind;
  occurredEnd: string | null;
  occurredLabel: string | null;
  occurredStart: string | null;
  occurredTimezone: string;
  revision: number;
  title: string;
  trackId: string;
  updatedAt: string;
};

export type TimelineTrack = {
  id: string;
  isHidden: boolean;
  items: TimelineEntry[];
  name: string;
  sortOrder: number;
  systemKey: string | null;
};

export type TimelineWorkspace = {
  inboxCount: number | undefined;
  loadError: string | null;
  tracks: TimelineTrack[];
  viewer: Viewer;
};

type TimelineRow = {
  body: string | null;
  date_precision: TimelineDatePrecision | null;
  entry_id: string | null;
  entry_type: string | null;
  item_sort_order: number | null;
  occurred_end: string | null;
  occurred_label: string | null;
  occurred_start: string | null;
  occurred_timezone: string | null;
  revision: number | null;
  timeline_kind: TimelineKind | null;
  title: string | null;
  track_id: string;
  track_is_hidden: boolean;
  track_name: string;
  track_sort_order: number;
  track_system_key: string | null;
  updated_at: string | null;
};

export async function getTimelineWorkspace(): Promise<TimelineWorkspace | null> {
  const context = await getAuthenticatedContext();

  if (!context) {
    return null;
  }

  const [timeline, inbox] = await Promise.all([
    context.client.rpc("timeline_workspace", { p_include_hidden: false }),
    context.client
      .from("entries")
      .select("id", { count: "exact", head: true })
      .eq("owner_id", context.userId)
      .eq("inbox_status", "unreviewed")
      .is("deleted_at", null),
  ]);
  const rows = timeline.error ? null : timelineRows(timeline.data);

  return {
    inboxCount: inbox.error ? undefined : (inbox.count ?? 0),
    loadError:
      timeline.error || !rows
        ? "MemoTrail could not load your Timeline. Refresh to try again."
        : null,
    tracks: rows ? tracksFromRows(rows) : [],
    viewer: context.viewer,
  };
}

function tracksFromRows(rows: TimelineRow[]) {
  const tracks = new Map<string, TimelineTrack>();

  for (const row of rows) {
    let track = tracks.get(row.track_id);

    if (!track) {
      track = {
        id: row.track_id,
        isHidden: row.track_is_hidden,
        items: [],
        name: row.track_name,
        sortOrder: row.track_sort_order,
        systemKey: row.track_system_key,
      };
      tracks.set(row.track_id, track);
    }

    if (row.entry_id) {
      track.items.push({
        body: row.body ?? "",
        datePrecision: row.date_precision ?? "unknown",
        entryType: row.entry_type ?? "standard",
        id: row.entry_id,
        kind: row.timeline_kind ?? "event",
        occurredEnd: row.occurred_end,
        occurredLabel: row.occurred_label,
        occurredStart: row.occurred_start,
        occurredTimezone: row.occurred_timezone ?? "UTC",
        revision: row.revision ?? 1,
        title: row.title ?? "Untitled moment",
        trackId: row.track_id,
        updatedAt: row.updated_at ?? "",
      });
    }
  }

  return [...tracks.values()]
    .sort((a, b) => a.sortOrder - b.sortOrder || a.name.localeCompare(b.name))
    .map((track) => ({
      ...track,
      items: track.items.sort(
        (a, b) =>
          (a.occurredStart ? Date.parse(a.occurredStart) : Infinity) -
            (b.occurredStart ? Date.parse(b.occurredStart) : Infinity) ||
          a.title.localeCompare(b.title),
      ),
    }));
}

function timelineRows(value: unknown): TimelineRow[] | null {
  if (!Array.isArray(value)) {
    return null;
  }

  return value.every(isTimelineRow) ? value : null;
}

function isTimelineRow(value: unknown): value is TimelineRow {
  if (!isRecord(value)) {
    return false;
  }

  const hasTrack =
    typeof value.track_id === "string" &&
    typeof value.track_name === "string" &&
    nullableString(value.track_system_key) &&
    typeof value.track_sort_order === "number" &&
    typeof value.track_is_hidden === "boolean";

  if (!hasTrack) {
    return false;
  }

  if (value.entry_id === null) {
    return true;
  }

  return (
    typeof value.entry_id === "string" &&
    typeof value.body === "string" &&
    typeof value.entry_type === "string" &&
    typeof value.title === "string" &&
    (value.timeline_kind === "stage" || value.timeline_kind === "event") &&
    nullableString(value.occurred_start) &&
    nullableString(value.occurred_end) &&
    nullableString(value.occurred_label) &&
    nullableString(value.occurred_timezone) &&
    typeof value.revision === "number" &&
    typeof value.updated_at === "string" &&
    typeof value.date_precision === "string"
  );
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function nullableString(value: unknown) {
  return value === null || typeof value === "string";
}
