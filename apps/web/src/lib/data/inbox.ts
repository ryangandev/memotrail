import "server-only";

import { cache } from "react";
import { createClient } from "@/lib/supabase/server";
import {
  validTimezone,
  type Occurrence,
  type OccurrencePrecision,
} from "./occurrence";
import { entryRichTextFromMetadata, type EntryRichText } from "./rich-text";
import { isWikiItemKind, type WikiItemKind } from "./wiki-item";
import {
  existingLocationFromRow,
  type ExistingLocation,
  type LocationSelection,
} from "@/lib/locations/location";

export type InboxEntry = Occurrence & {
  body: string;
  bodyRich: EntryRichText | null;
  createdAt: string;
  id: string;
  itemKind: WikiItemKind;
  itemSubtype: string;
  location?: LocationSelection | null;
  revision: number;
  tagNames: string[];
  title: string | null;
};

export type Viewer = {
  email: string;
  id: string;
  initial: string;
  name: string;
};

export type InboxWorkspace = {
  entries: InboxEntry[];
  loadError: string | null;
  tagOptions: string[];
  viewer: Viewer;
};

type Claims = Record<string, unknown>;

type EntryRow = {
  body: string;
  created_at: string;
  id: string;
  item_kind: string;
  item_subtype: string;
  metadata: unknown;
  occurred_start: string | null;
  occurred_end: string | null;
  occurred_label: string | null;
  date_precision: OccurrencePrecision;
  occurred_timezone: string | null;
  revision: number;
  title: string | null;
};

type EntryTagRow = {
  entry_id: string;
  tag: { name: string } | null;
};

type NameRow = {
  name: string;
};

type EntryLocationRow = {
  entry_id: string;
  location: unknown;
};

export const getAuthenticatedContext = cache(
  async function getAuthenticatedContext() {
    try {
      const client = await createClient();
      const { data, error } = await client.auth.getClaims();

      if (error || !data?.claims) {
        return null;
      }

      const claims = data.claims as Claims;
      const userId = stringValue(claims.sub);

      if (!userId) {
        return null;
      }

      return {
        client,
        userId,
        viewer: viewerFromClaims(userId, claims),
      };
    } catch {
      return null;
    }
  },
);

export async function loadEntryRichTextMap(
  context: NonNullable<Awaited<ReturnType<typeof getAuthenticatedContext>>>,
  entries: readonly { body: string; id: string }[],
) {
  const expectedBodies = new Map(
    entries.map((entry) => [entry.id, entry.body] as const),
  );
  if (expectedBodies.size === 0) return new Map<string, EntryRichText>();

  const { data, error } = await context.client
    .from("entries")
    .select("id,body,metadata")
    .eq("owner_id", context.userId)
    .in("id", [...expectedBodies.keys()])
    .returns<{ body: string; id: string; metadata: unknown }[]>();

  if (error) return new Map<string, EntryRichText>();

  const values = new Map<string, EntryRichText>();
  for (const row of data ?? []) {
    if (expectedBodies.get(row.id) !== row.body) continue;
    const richText = entryRichTextFromMetadata(row.metadata, row.body);
    if (richText) values.set(row.id, richText);
  }
  return values;
}

export async function getInboxWorkspace(
  focusedEntryId: string | null = null,
): Promise<InboxWorkspace | null> {
  const context = await getAuthenticatedContext();

  if (!context) {
    return null;
  }

  const entryColumns =
    "id,title,body,metadata,item_kind,item_subtype,created_at,occurred_start,occurred_end,occurred_label,date_precision,occurred_timezone,revision";
  const inboxRequest = context.client
    .from("entries")
    .select(entryColumns)
    .eq("owner_id", context.userId)
    .eq("inbox_status", "unreviewed")
    .is("deleted_at", null)
    .order("created_at", { ascending: false })
    .limit(50)
    .returns<EntryRow[]>();
  const focusedRequest = focusedEntryId
    ? context.client
        .from("entries")
        .select(entryColumns)
        .eq("owner_id", context.userId)
        .eq("id", focusedEntryId)
        .eq("inbox_status", "unreviewed")
        .is("deleted_at", null)
        .limit(1)
        .returns<EntryRow[]>()
    : Promise.resolve({ data: [] as EntryRow[], error: null });
  const [inbox, focused] = await Promise.all([inboxRequest, focusedRequest]);

  if (inbox.error || focused.error) {
    return unavailableWorkspace(context.viewer);
  }

  const rows = [...(focused.data ?? []), ...(inbox.data ?? [])].filter(
    (entry, index, values) =>
      values.findIndex((candidate) => candidate.id === entry.id) === index,
  );
  const entryIds = rows.map((entry) => entry.id);
  const [entryTags, entryLocations, tags] = await Promise.all([
    loadEntryTags(context, entryIds),
    loadEntryLocations(context, entryIds),
    context.client
      .from("tags")
      .select("name")
      .eq("owner_id", context.userId)
      .order("name")
      .returns<NameRow[]>(),
  ]);

  if (entryTags.error || entryLocations.error) {
    return unavailableWorkspace(context.viewer);
  }

  const tagNamesByEntry = namesByEntry(entryTags.data ?? []);
  const locationsByEntry = new Map(
    (entryLocations.data ?? []).flatMap((row) => {
      const location = existingLocationFromRow(row.location);
      return location ? [[row.entry_id, location] as const] : [];
    }),
  );

  return {
    entries: rows.map((row) =>
      entryFromRow(
        row,
        tagNamesByEntry.get(row.id) ?? [],
        locationsByEntry.get(row.id) ?? null,
      ),
    ),
    loadError: null,
    tagOptions: tags.error ? [] : (tags.data ?? []).map((tag) => tag.name),
    viewer: context.viewer,
  };
}

export function entryFromRow(
  row: EntryRow,
  tagNames: string[],
  location: ExistingLocation | null = null,
): InboxEntry {
  return {
    body: row.body,
    bodyRich: entryRichTextFromMetadata(row.metadata, row.body),
    createdAt: row.created_at,
    id: row.id,
    itemKind: isWikiItemKind(row.item_kind) ? row.item_kind : "entry",
    itemSubtype:
      typeof row.item_subtype === "string" && row.item_subtype
        ? row.item_subtype
        : "entry",
    location,
    occurredAt: row.occurred_start,
    occurredEnd: row.occurred_end,
    occurredLabel: row.occurred_label,
    datePrecision:
      row.occurred_start || row.date_precision !== "exact"
        ? row.date_precision
        : "unknown",
    occurredTimezone: validTimezone(row.occurred_timezone)
      ? row.occurred_timezone
      : "UTC",
    revision: row.revision,
    tagNames,
    title: stringValue(row.title),
  };
}

function loadEntryLocations(
  context: NonNullable<Awaited<ReturnType<typeof getAuthenticatedContext>>>,
  entryIds: string[],
) {
  if (entryIds.length === 0) {
    return Promise.resolve({ data: [] as EntryLocationRow[], error: null });
  }
  return context.client
    .from("entry_places")
    .select(
      "entry_id,location:locations!entry_places_location_id_owner_id_fkey(id,revision,name,formatted_address,address,city,region,postal_code,country,country_code,latitude,longitude,timezone_id,result_type)",
    )
    .eq("owner_id", context.userId)
    .eq("relationship", "primary")
    .in("entry_id", entryIds)
    .returns<EntryLocationRow[]>();
}

function loadEntryTags(
  context: NonNullable<Awaited<ReturnType<typeof getAuthenticatedContext>>>,
  entryIds: string[],
) {
  if (entryIds.length === 0) {
    return Promise.resolve({ data: [] as EntryTagRow[], error: null });
  }

  return context.client
    .from("entry_tags")
    .select("entry_id,tag:tags(name)")
    .eq("owner_id", context.userId)
    .in("entry_id", entryIds)
    .returns<EntryTagRow[]>();
}

function namesByEntry(rows: EntryTagRow[]) {
  const names = new Map<string, string[]>();

  for (const row of rows) {
    if (!row.tag) {
      continue;
    }

    const currentNames = names.get(row.entry_id) ?? [];
    currentNames.push(row.tag.name);
    names.set(row.entry_id, currentNames);
  }

  return names;
}

function unavailableWorkspace(viewer: Viewer): InboxWorkspace {
  return {
    entries: [],
    loadError: "MemoTrail could not load your Inbox. Refresh to try again.",
    tagOptions: [],
    viewer,
  };
}

function viewerFromClaims(id: string, claims: Claims): Viewer {
  const metadata = asRecord(claims.user_metadata);
  const email = stringValue(claims.email) ?? "Signed-in account";
  const name =
    stringValue(metadata.full_name) ??
    stringValue(metadata.name) ??
    email.split("@")[0] ??
    "MemoTrail";
  const initial = name.trim().charAt(0).toLocaleUpperCase() || "M";

  return { email, id, initial, name };
}

function asRecord(value: unknown): Claims {
  if (typeof value === "object" && value !== null) {
    return value as Claims;
  }

  return {};
}

function stringValue(value: unknown) {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}
