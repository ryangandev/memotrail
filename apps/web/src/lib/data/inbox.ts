import "server-only";

import { createClient } from "@/lib/supabase/server";

export type InboxEntry = {
  body: string;
  collectionNames: string[];
  createdAt: string;
  entryType: "first_time" | "standard";
  id: string;
  occurredAt: string;
  occurredTimezone: string | null;
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
  collectionOptions: string[];
  entries: InboxEntry[];
  loadError: string | null;
  tagOptions: string[];
  viewer: Viewer;
};

type Claims = Record<string, unknown>;

type EntryRow = {
  body: string;
  created_at: string;
  entry_type: "first_time" | "standard";
  id: string;
  occurred_start: string | null;
  occurred_timezone: string | null;
  revision: number;
  title: string | null;
};

type EntryCollectionRow = {
  collection: { name: string } | null;
  entry_id: string;
};

type EntryTagRow = {
  entry_id: string;
  tag: { name: string } | null;
};

type NameRow = {
  name: string;
};

export async function getAuthenticatedContext() {
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
}

export async function getInboxWorkspace(): Promise<InboxWorkspace | null> {
  const context = await getAuthenticatedContext();

  if (!context) {
    return null;
  }

  const { data, error } = await context.client
    .from("entries")
    .select(
      "id,title,body,entry_type,created_at,occurred_start,occurred_timezone,revision",
    )
    .eq("owner_id", context.userId)
    .eq("inbox_status", "unreviewed")
    .is("deleted_at", null)
    .order("created_at", { ascending: false })
    .limit(50)
    .returns<EntryRow[]>();

  if (error) {
    return unavailableWorkspace(context.viewer);
  }

  const rows = data ?? [];
  const entryIds = rows.map((entry) => entry.id);
  const [entryCollections, entryTags, collections, tags] = await Promise.all([
    loadEntryCollections(context, entryIds),
    loadEntryTags(context, entryIds),
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

  if (entryCollections.error || entryTags.error) {
    return unavailableWorkspace(context.viewer);
  }

  const collectionNamesByEntry = namesByEntry(
    entryCollections.data ?? [],
    "collection",
  );
  const tagNamesByEntry = namesByEntry(entryTags.data ?? [], "tag");

  return {
    collectionOptions: collections.error
      ? []
      : (collections.data ?? []).map((collection) => collection.name),
    entries: rows.map((row) =>
      entryFromRow(
        row,
        collectionNamesByEntry.get(row.id) ?? [],
        tagNamesByEntry.get(row.id) ?? [],
      ),
    ),
    loadError: null,
    tagOptions: tags.error ? [] : (tags.data ?? []).map((tag) => tag.name),
    viewer: context.viewer,
  };
}

function entryFromRow(
  row: EntryRow,
  collectionNames: string[],
  tagNames: string[],
): InboxEntry {
  return {
    body: row.body,
    collectionNames,
    createdAt: row.created_at,
    entryType: row.entry_type,
    id: row.id,
    occurredAt: row.occurred_start ?? row.created_at,
    occurredTimezone: stringValue(row.occurred_timezone),
    revision: row.revision,
    tagNames,
    title: stringValue(row.title),
  };
}

function loadEntryCollections(
  context: NonNullable<Awaited<ReturnType<typeof getAuthenticatedContext>>>,
  entryIds: string[],
) {
  if (entryIds.length === 0) {
    return Promise.resolve({ data: [] as EntryCollectionRow[], error: null });
  }

  return context.client
    .from("entry_collections")
    .select("entry_id,collection:collections(name)")
    .eq("owner_id", context.userId)
    .in("entry_id", entryIds)
    .returns<EntryCollectionRow[]>();
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

function namesByEntry(
  rows: EntryCollectionRow[] | EntryTagRow[],
  relationship: "collection" | "tag",
) {
  const names = new Map<string, string[]>();

  for (const row of rows) {
    const item =
      relationship === "collection"
        ? (row as EntryCollectionRow).collection
        : (row as EntryTagRow).tag;

    if (!item) {
      continue;
    }

    const currentNames = names.get(row.entry_id) ?? [];
    currentNames.push(item.name);
    names.set(row.entry_id, currentNames);
  }

  return names;
}

function unavailableWorkspace(viewer: Viewer): InboxWorkspace {
  return {
    collectionOptions: [],
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
