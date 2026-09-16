import "server-only";

import { displayImageURLs } from "@/lib/media/urls";
import { getAuthenticatedContext, type Viewer } from "@/lib/data/inbox";
import {
  parseHomePlaceOptions,
  parseHomeRows,
  type HomePlaceOption,
  type HomeRecord,
} from "@/lib/data/home-record";
import {
  parseVehicleRows,
  type VehicleRecord,
} from "@/lib/data/vehicle-record";
import {
  parseFirstTimeRows,
  type FirstTimeEntry,
} from "@/lib/data/first-times";
import type {
  TimelineDatePrecision,
  TimelineKind,
} from "@/lib/data/timeline-input";
import {
  storedBirthDate,
  storedProfileTimezone,
} from "@/lib/data/profile-input";
import { isWikiItemKind, type WikiItemKind } from "@/lib/data/wiki-item";

export type TimelineEntry = {
  body: string;
  collectionNames: string[];
  datePrecision: TimelineDatePrecision;
  id: string;
  itemKind: WikiItemKind;
  itemSubtype: string;
  kind: TimelineKind;
  occurredEnd: string | null;
  occurredLabel: string | null;
  occurredStart: string | null;
  occurredTimezone: string;
  revision: number;
  tagNames: string[];
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
  birthDate: string | null;
  birthDateAvailable: boolean;
  collectionOptions: string[];
  defaultTimezone: string;
  firstTimes: FirstTimeEntry[];
  homes: HomeRecord[];
  inboxCount: number | undefined;
  loadError: string | null;
  placeOptions: HomePlaceOption[];
  tagOptions: string[];
  tracks: TimelineTrack[];
  vehicles: VehicleRecord[];
  viewer: Viewer;
};

type NameRow = { name: string };

type TimelineRow = {
  body: string | null;
  collection_names: string[];
  date_precision: TimelineDatePrecision | null;
  entry_id: string | null;
  item_kind: WikiItemKind | null;
  item_subtype: string | null;
  item_sort_order: number | null;
  occurred_end: string | null;
  occurred_label: string | null;
  occurred_start: string | null;
  occurred_timezone: string | null;
  revision: number | null;
  tag_names: string[];
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

  const [
    timeline,
    inbox,
    profile,
    homes,
    vehicles,
    firstTimes,
    places,
    collections,
    tags,
  ] = await Promise.all([
    context.client.rpc("timeline_workspace_with_organization", {
      p_include_hidden: false,
    }),
    context.client
      .from("entries")
      .select("id", { count: "exact", head: true })
      .eq("owner_id", context.userId)
      .eq("inbox_status", "unreviewed")
      .is("deleted_at", null),
    context.client
      .from("profiles")
      .select("*")
      .eq("user_id", context.userId)
      .single(),
    context.client.rpc("homes_workspace", { p_limit: 100, p_offset: 0 }),
    context.client.rpc("vehicles_workspace", { p_limit: 100, p_offset: 0 }),
    context.client.rpc("first_times_workspace_with_occurrence"),
    context.client
      .from("places")
      .select("id,name,address,city,region,country,latitude,longitude,notes")
      .eq("owner_id", context.userId)
      .is("deleted_at", null)
      .order("name"),
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
  ]);
  const rows = timeline.error ? null : timelineRows(timeline.data);
  const timelineEntryIds = new Set(
    (rows ?? []).flatMap((row) => (row.entry_id ? [row.entry_id] : [])),
  );
  const homeRows = (
    homes.error ? [] : (parseHomeRows(homes.data) ?? [])
  ).filter((home) => timelineEntryIds.has(home.id));
  const vehicleRows = (
    vehicles.error ? [] : (parseVehicleRows(vehicles.data) ?? [])
  ).filter((vehicle) => timelineEntryIds.has(vehicle.id));
  const firstTimeRows = (
    firstTimes.error ? [] : (parseFirstTimeRows(firstTimes.data) ?? [])
  ).filter((entry) => timelineEntryIds.has(entry.entry_id));
  const imageUrls = await displayImageURLs(
    context.client,
    [
      ...homeRows.flatMap((home) => home.attachments),
      ...vehicleRows.flatMap((vehicle) => vehicle.attachments),
      ...firstTimeRows.flatMap((entry) => entry.attachments),
    ].map((attachment) => attachment.objectPath),
  );
  const profileBirthDate = storedBirthDate(profile.error ? null : profile.data);
  const profileTimezone = storedProfileTimezone(
    profile.error ? null : profile.data,
  );

  return {
    birthDate: profileBirthDate.birthDate,
    birthDateAvailable: profileBirthDate.available,
    collectionOptions: collections.error
      ? []
      : (collections.data ?? []).map((item) => item.name),
    defaultTimezone: profileTimezone.timezone,
    firstTimes: firstTimeRows.map((entry) => ({
      attachments: entry.attachments.map((attachment) => ({
        ...attachment,
        imageUrl: imageUrls.get(attachment.objectPath) ?? null,
      })),
      body: entry.body,
      collectionNames: entry.collection_names,
      datePrecision: entry.date_precision,
      id: entry.entry_id,
      inboxStatus: entry.inbox_status,
      occurredEnd: entry.occurred_end,
      occurredLabel: entry.occurred_label,
      occurredStart: entry.occurred_start,
      occurredTimezone: entry.occurred_timezone,
      revision: entry.revision,
      tagNames: entry.tag_names,
      title: entry.title,
      updatedAt: entry.updated_at,
    })),
    homes: homeRows.map((home) => ({
      ...home,
      attachments: home.attachments.map((attachment) => ({
        ...attachment,
        imageUrl: imageUrls.get(attachment.objectPath) ?? null,
      })),
    })),
    inboxCount: inbox.error ? undefined : (inbox.count ?? 0),
    loadError:
      timeline.error || !rows
        ? "MemoTrail could not load your Timeline. Refresh to try again."
        : null,
    placeOptions: places.error
      ? []
      : (parseHomePlaceOptions(places.data) ?? []),
    tagOptions: tags.error ? [] : (tags.data ?? []).map((item) => item.name),
    tracks: rows ? tracksFromRows(rows) : [],
    vehicles: vehicleRows.map((vehicle) => ({
      ...vehicle,
      attachments: vehicle.attachments.map((attachment) => ({
        ...attachment,
        imageUrl: imageUrls.get(attachment.objectPath) ?? null,
      })),
    })),
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
        collectionNames: row.collection_names,
        datePrecision: row.date_precision ?? "unknown",
        id: row.entry_id,
        itemKind: row.item_kind ?? "event",
        itemSubtype: row.item_subtype ?? "other",
        kind: row.timeline_kind ?? "event",
        occurredEnd: row.occurred_end,
        occurredLabel: row.occurred_label,
        occurredStart: row.occurred_start,
        occurredTimezone: row.occurred_timezone ?? "UTC",
        revision: row.revision ?? 1,
        tagNames: row.tag_names,
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
    isWikiItemKind(value.item_kind) &&
    typeof value.item_subtype === "string" &&
    typeof value.title === "string" &&
    (value.timeline_kind === "stage" || value.timeline_kind === "event") &&
    nullableString(value.occurred_start) &&
    nullableString(value.occurred_end) &&
    nullableString(value.occurred_label) &&
    nullableString(value.occurred_timezone) &&
    stringArray(value.collection_names) &&
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
