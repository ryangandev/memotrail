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
import type {
  ExistingLocation,
  LocationSelection,
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
