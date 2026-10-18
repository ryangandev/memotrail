import "server-only";

import { getAuthenticatedContext, type Viewer } from "@/lib/data/inbox";
import {
  storedBirthDate,
  storedProfileTimezone,
} from "@/lib/data/profile-input";
import { isWikiItemKind, type WikiItemKind } from "@/lib/data/wiki-item";
import {
  isMilestoneShape,
  isTimelineLane,
  timelineLaneLabels,
  timelineLanes,
  type MilestoneShape,
  type TimelineLane,
} from "@/lib/data/milestone";
import {
  entryDisplayTitle,
  storedOccurrence,
  type OccurrencePrecision,
} from "@/lib/data/occurrence";

export type TimelineEntry = {
  body: string;
  datePrecision: OccurrencePrecision;
  id: string;
  isFirstTime: boolean;
  itemKind: WikiItemKind;
  itemSubtype: string;
  lane: TimelineLane;
  occurredEnd: string | null;
  occurredLabel: string | null;
  occurredStart: string | null;
  occurredTimezone: string;
  revision: number;
  shape: MilestoneShape;
  tagNames: string[];
  /** Its title, or its date when it has none. */
  title: string;
  updatedAt: string;
};

export type TimelineLaneGroup = {
  items: TimelineEntry[];
  key: TimelineLane;
  name: string;
};

export type TimelineWorkspace = {
  birthDate: string | null;
  birthDateAvailable: boolean;
  defaultTimezone: string;
  lanes: TimelineLaneGroup[];
  loadError: string | null;
  tagOptions: string[];
  viewer: Viewer;
};

type NameRow = { name: string };

type TimelineRow = {
  body: string;
  date_precision: string;
  entry_id: string;
  is_first_time: boolean;
  item_kind: WikiItemKind;
  item_subtype: string;
  lane: TimelineLane;
  occurred_end: string | null;
  occurred_label: string | null;
  occurred_start: string | null;
  occurred_timezone: string;
  revision: number;
  shape: MilestoneShape;
  tag_names: string[];
  title: string;
  updated_at: string;
};

export async function getTimelineWorkspace(): Promise<TimelineWorkspace | null> {
  const context = await getAuthenticatedContext();

  if (!context) {
    return null;
  }

  const [timeline, profile, tags] = await Promise.all([
    context.client.rpc("timeline_workspace"),
    context.client
      .from("profiles")
      .select("*")
      .eq("user_id", context.userId)
      .single(),
    context.client
      .from("tags")
      .select("name")
      .eq("owner_id", context.userId)
      .order("name")
      .returns<NameRow[]>(),
  ]);
  const rows = timeline.error ? null : timelineRows(timeline.data);
  const profileBirthDate = storedBirthDate(profile.error ? null : profile.data);
  const profileTimezone = storedProfileTimezone(
    profile.error ? null : profile.data,
  );

  return {
    birthDate: profileBirthDate.birthDate,
    birthDateAvailable: profileBirthDate.available,
    defaultTimezone: profileTimezone.timezone,
    lanes: timelineLaneGroups((rows ?? []).map(timelineEntryFromRow)),
    loadError: rows
      ? null
      : "MemoTrail could not load your Timeline. Refresh to try again.",
    tagOptions: tags.error ? [] : (tags.data ?? []).map((item) => item.name),
    viewer: context.viewer,
  };
}

// Every lane appears, in a fixed order, even when it is empty.
export function timelineLaneGroups(
  entries: TimelineEntry[],
): TimelineLaneGroup[] {
  return timelineLanes.map((key) => ({
    items: entries
      .filter((entry) => entry.lane === key)
      .sort(
        (a, b) =>
          (a.occurredStart ? Date.parse(a.occurredStart) : Infinity) -
            (b.occurredStart ? Date.parse(b.occurredStart) : Infinity) ||
          a.title.localeCompare(b.title),
      ),
    key,
    name: timelineLaneLabels[key],
  }));
}

function timelineEntryFromRow(row: TimelineRow): TimelineEntry {
  const occurrence = storedOccurrence({
    datePrecision: row.date_precision,
    occurredEnd: row.occurred_end,
    occurredLabel: row.occurred_label,
    occurredStart: row.occurred_start,
    occurredTimezone: row.occurred_timezone,
  });
  return {
    body: row.body,
    datePrecision: occurrence.datePrecision,
    id: row.entry_id,
    isFirstTime: row.is_first_time,
    itemKind: row.item_kind,
    itemSubtype: row.item_subtype,
    lane: row.lane,
    occurredEnd: row.occurred_end,
    occurredLabel: row.occurred_label,
    occurredStart: row.occurred_start,
    occurredTimezone: row.occurred_timezone,
    revision: row.revision,
    shape: row.shape,
    tagNames: row.tag_names,
    title: entryDisplayTitle(row.title, occurrence),
    updatedAt: row.updated_at,
  };
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

  return (
    typeof value.entry_id === "string" &&
    typeof value.body === "string" &&
    isWikiItemKind(value.item_kind) &&
    typeof value.item_subtype === "string" &&
    typeof value.title === "string" &&
    isTimelineLane(value.lane) &&
    isMilestoneShape(value.shape) &&
    typeof value.is_first_time === "boolean" &&
    nullableString(value.occurred_start) &&
    nullableString(value.occurred_end) &&
    nullableString(value.occurred_label) &&
    typeof value.occurred_timezone === "string" &&
    stringArray(value.tag_names) &&
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

function stringArray(value: unknown): value is string[] {
  return (
    Array.isArray(value) && value.every((item) => typeof item === "string")
  );
}
