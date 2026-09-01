import "server-only";

import { createClient } from "@/lib/supabase/server";

export type InboxEntry = {
  body: string;
  createdAt: string;
  id: string;
  occurredAt: string;
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
  viewer: Viewer;
};

type Claims = Record<string, unknown>;

type EntryRow = {
  body: string;
  created_at: string;
  id: string;
  occurred_start: string | null;
  title: string | null;
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
    .select("id,title,body,created_at,occurred_start")
    .eq("owner_id", context.userId)
    .eq("inbox_status", "unreviewed")
    .is("deleted_at", null)
    .order("created_at", { ascending: false })
    .limit(50)
    .returns<EntryRow[]>();

  return {
    entries: error ? [] : (data ?? []).map(entryFromRow),
    loadError: error
      ? "MemoTrail could not load your Inbox. Refresh to try again."
      : null,
    viewer: context.viewer,
  };
}

function entryFromRow(row: EntryRow): InboxEntry {
  return {
    body: row.body,
    createdAt: row.created_at,
    id: row.id,
    occurredAt: row.occurred_start ?? row.created_at,
    title: stringValue(row.title),
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
