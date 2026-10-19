import "server-only";
import { displayImageURLs } from "@/lib/media/urls";

import { getAuthenticatedContext, type Viewer } from "./inbox";
import { loadTagOptions } from "./tag-options";
import { storedProfileTimezone } from "./profile-input";
import { getPrimaryEntryLocations } from "./entry-locations";
import type { LocationSelection } from "@/lib/locations/location";
import {
  entryImageMimeTypes,
  type EntryImageMimeType,
} from "./entry-photo-input";
import {
  entryDisplayTitle,
  occurrencePrecisions,
  storedOccurrence,
  type OccurrencePrecision,
} from "./occurrence";

export type FirstTimeAttachment = {
  bucketId: string;
  byteSize: number;
  createdAt: string;
  id: string;
  imageUrl: string | null;
  mimeType: EntryImageMimeType;
  objectPath: string;
  originalFilename: string | null;
  parentAttachmentId: string | null;
  pixelHeight: number | null;
  pixelWidth: number | null;
  variant: "display" | "original" | "thumbnail";
};

export type FirstTimeEntry = {
  attachments: FirstTimeAttachment[];
  body: string;
  datePrecision: OccurrencePrecision;
  id: string;
  /** A First Time can also be a Chapter, which spans a stretch of time. */
  isChapter: boolean;
  location?: LocationSelection | null;
  occurredLabel: string | null;
  occurredStart: string | null;
  occurredEnd: string | null;
  occurredTimezone: string | null;
  revision: number;
  tagNames: string[];
  /** Its title, or its date when it has none. */
  title: string;
  updatedAt: string;
};

export type FirstTimesWorkspace = {
  defaultTimezone: string;
  entries: FirstTimeEntry[];
  loadError: string | null;
  tagOptions: string[];
  viewer: Viewer;
};

type FirstTimeRow = {
  attachments: unknown;
  body: string;
  date_precision: OccurrencePrecision;
  entry_id: string;
  is_chapter: boolean;
  occurred_label: string | null;
  occurred_start: string | null;
  occurred_end: string | null;
  occurred_timezone: string | null;
  revision: number;
  tag_names: string[];
  title: string;
  updated_at: string;
};

// First Times are the Entries marked as a First Time.
export async function getFirstTimesWorkspace(): Promise<FirstTimesWorkspace | null> {
  const context = await getAuthenticatedContext();

  if (!context) {
    return null;
  }

  const [firstTimes, profile, tags] = await Promise.all([
    context.client.rpc("first_times_workspace"),
    context.client
      .from("profiles")
      .select("*")
      .eq("user_id", context.userId)
      .single(),
    loadTagOptions(context.client, context.userId),
  ]);
  const rows = firstTimes.error ? null : parseFirstTimeRows(firstTimes.data);

  if (!rows) {
    return unavailableWorkspace(context.viewer);
  }

  const locations = await getPrimaryEntryLocations(
    context,
    rows.map((row) => row.entry_id),
  );
  if (!locations) {
    return unavailableWorkspace(context.viewer);
  }

  const attachments = rows.flatMap((row) => row.attachments);
  const signedUrls = await signedImageUrls(context.client, attachments);

  return {
    defaultTimezone: storedProfileTimezone(profile.error ? null : profile.data)
      .timezone,
    entries: rows.map((row) => ({
      attachments: row.attachments.map((attachment) => ({
        ...attachment,
        imageUrl: signedUrls.get(attachment.objectPath) ?? null,
      })),
      body: row.body,
      datePrecision: row.date_precision,
      id: row.entry_id,
      isChapter: row.is_chapter,
      location: locations.get(row.entry_id) ?? null,
      occurredLabel: row.occurred_label,
      occurredStart: row.occurred_start,
      occurredEnd: row.occurred_end,
      occurredTimezone: row.occurred_timezone,
      revision: row.revision,
      tagNames: row.tag_names,
      title: entryDisplayTitle(
        row.title,
        storedOccurrence({
          datePrecision: row.date_precision,
          occurredEnd: row.occurred_end,
          occurredLabel: row.occurred_label,
          occurredStart: row.occurred_start,
          occurredTimezone: row.occurred_timezone,
        }),
      ),
      updatedAt: row.updated_at,
    })),
    loadError: null,
    tagOptions: tags ?? [],
    viewer: context.viewer,
  };
}

async function signedImageUrls(
  client: NonNullable<
    Awaited<ReturnType<typeof getAuthenticatedContext>>
  >["client"],
  attachments: FirstTimeAttachment[],
) {
  const paths = [...new Set(attachments.map((item) => item.objectPath))];
  return displayImageURLs(client, paths);
}

export function parseFirstTimeRows(value: unknown):
  | (FirstTimeRow & {
      attachments: FirstTimeAttachment[];
    })[]
  | null {
  if (!Array.isArray(value)) {
    return null;
  }

  const rows: (FirstTimeRow & { attachments: FirstTimeAttachment[] })[] = [];

  for (const item of value) {
    if (!isRecord(item)) {
      return null;
    }

    const attachments = parseAttachments(item.attachments);

    if (
      !attachments ||
      typeof item.entry_id !== "string" ||
      typeof item.is_chapter !== "boolean" ||
      typeof item.title !== "string" ||
      typeof item.body !== "string" ||
      typeof item.date_precision !== "string" ||
      !occurrencePrecisions.includes(
        item.date_precision as OccurrencePrecision,
      ) ||
      !nullableString(item.occurred_start) ||
      !nullableString(item.occurred_end) ||
      !nullableString(item.occurred_label) ||
      !nullableString(item.occurred_timezone) ||
      typeof item.revision !== "number" ||
      typeof item.updated_at !== "string" ||
      !stringArray(item.tag_names)
    ) {
      return null;
    }

    rows.push({
      attachments,
      body: item.body,
      date_precision: item.date_precision as OccurrencePrecision,
      entry_id: item.entry_id,
      is_chapter: item.is_chapter,
      occurred_label: item.occurred_label,
      occurred_start: item.occurred_start,
      occurred_end: item.occurred_end,
      occurred_timezone: item.occurred_timezone,
      revision: item.revision,
      tag_names: item.tag_names,
      title: item.title,
      updated_at: item.updated_at,
    });
  }

  return rows;
}

function parseAttachments(value: unknown): FirstTimeAttachment[] | null {
  if (!Array.isArray(value)) {
    return null;
  }

  const attachments: FirstTimeAttachment[] = [];

  for (const item of value) {
    if (
      !isRecord(item) ||
      typeof item.id !== "string" ||
      typeof item.bucketId !== "string" ||
      typeof item.objectPath !== "string" ||
      typeof item.mimeType !== "string" ||
      !entryImageMimeTypes.includes(item.mimeType as EntryImageMimeType) ||
      typeof item.byteSize !== "number" ||
      typeof item.createdAt !== "string" ||
      !nullableString(item.parentAttachmentId) ||
      !nullableString(item.originalFilename) ||
      !nullableNumber(item.pixelWidth) ||
      !nullableNumber(item.pixelHeight) ||
      (item.variant !== "original" &&
        item.variant !== "display" &&
        item.variant !== "thumbnail")
    ) {
      return null;
    }

    attachments.push({
      bucketId: item.bucketId,
      byteSize: item.byteSize,
      createdAt: item.createdAt,
      id: item.id,
      imageUrl: null,
      mimeType: item.mimeType as EntryImageMimeType,
      objectPath: item.objectPath,
      originalFilename: item.originalFilename,
      parentAttachmentId: item.parentAttachmentId,
      pixelHeight: item.pixelHeight,
      pixelWidth: item.pixelWidth,
      variant: item.variant,
    });
  }

  return attachments;
}

function unavailableWorkspace(viewer: Viewer): FirstTimesWorkspace {
  return {
    defaultTimezone: "UTC",
    entries: [],
    loadError:
      "MemoTrail could not load your First Times. Refresh to try again.",
    tagOptions: [],
    viewer,
  };
}

function stringArray(value: unknown): value is string[] {
  return (
    Array.isArray(value) && value.every((item) => typeof item === "string")
  );
}

function nullableNumber(value: unknown): value is number | null {
  return value === null || typeof value === "number";
}

function nullableString(value: unknown): value is string | null {
  return value === null || typeof value === "string";
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}
