import {
  firstTimeImageMimeTypes,
  type FirstTimeImageMimeType,
} from "./first-time-input";
import {
  goalHorizons,
  goalStatuses,
  type GoalHorizon,
  type GoalStatus,
} from "./goal-record-input";
import { isWikiItemKind, type WikiItemKind } from "./wiki-item";

export type GoalAttachment = {
  bucketId: string;
  byteSize: number | null;
  createdAt: string;
  id: string;
  imageUrl: string | null;
  mimeType: FirstTimeImageMimeType;
  objectPath: string;
  originalFilename: string | null;
  pixelHeight: number | null;
  pixelWidth: number | null;
};

export type GoalRelatedEntry = {
  body: string;
  id: string;
  itemKind: WikiItemKind;
  itemSubtype: string;
  occurredLabel: string | null;
  occurredStart: string | null;
  occurredTimezone: string | null;
  relationship: string;
  revision: number;
  title: string;
  updatedAt: string;
};

export type GoalRecord = {
  attachments: GoalAttachment[];
  body: string;
  createdAt: string;
  horizon: GoalHorizon;
  id: string;
  relatedEntries: GoalRelatedEntry[];
  revision: number;
  status: GoalStatus;
  tagNames: string[];
  targetDate: string | null;
  title: string;
  totalCount: number;
  updatedAt: string;
};

export type GoalLinkOption = {
  id: string;
  itemKind: WikiItemKind;
  itemSubtype: string;
  title: string;
  updatedAt: string;
};

export const goalHorizonLabels: Record<GoalHorizon, string> = {
  long_term: "Long-term",
  short_term: "Short-term",
  someday: "Someday",
};

export const goalStatusLabels: Record<GoalStatus, string> = {
  achieved: "Achieved",
  active: "Active",
  considering: "Considering",
  let_go: "Let go",
  paused: "Paused",
};

export function parseGoalRows(value: unknown): GoalRecord[] | null {
  if (!Array.isArray(value)) return null;
  const records: GoalRecord[] = [];
  for (const item of value) {
    const record = parseGoalRow(item);
    if (!record) return null;
    records.push(record);
  }
  return records;
}

export function parseGoalLinkOptions(value: unknown): GoalLinkOption[] | null {
  if (!Array.isArray(value)) return null;
  const options: GoalLinkOption[] = [];
  for (const item of value) {
    if (
      !isRecord(item) ||
      typeof item.id !== "string" ||
      !nullableString(item.title) ||
      !nullableString(item.body) ||
      !isWikiItemKind(item.item_kind) ||
      typeof item.item_subtype !== "string" ||
      typeof item.updated_at !== "string"
    ) {
      return null;
    }
    options.push({
      id: item.id,
      itemKind: item.item_kind,
      itemSubtype: item.item_subtype,
      title: entryOptionTitle(item.title, item.body),
      updatedAt: item.updated_at,
    });
  }
  return options;
}

export function goalTargetLabel(goal: GoalRecord) {
  if (!goal.targetDate) return "No target date";
  const date = new Date(`${goal.targetDate}T12:00:00Z`);
  if (Number.isNaN(date.getTime())) return "Target date unavailable";
  return `Target ${new Intl.DateTimeFormat("en", {
    day: "numeric",
    month: "short",
    timeZone: "UTC",
    year: "numeric",
  }).format(date)}`;
}

function parseGoalRow(value: unknown): GoalRecord | null {
  if (
    !isRecord(value) ||
    typeof value.entry_id !== "string" ||
    typeof value.title !== "string" ||
    typeof value.body !== "string" ||
    typeof value.revision !== "number" ||
    typeof value.created_at !== "string" ||
    typeof value.updated_at !== "string" ||
    typeof value.horizon !== "string" ||
    !goalHorizons.includes(value.horizon as GoalHorizon) ||
    typeof value.status !== "string" ||
    !goalStatuses.includes(value.status as GoalStatus) ||
    !nullableString(value.target_date) ||
    !stringArray(value.tag_names) ||
    typeof value.total_count !== "number"
  ) {
    return null;
  }

  const relatedEntries = parseRelatedEntries(value.related_entries);
  const attachments = parseAttachments(value.attachments);
  if (!relatedEntries || !attachments) return null;

  return {
    attachments,
    body: value.body,
    createdAt: value.created_at,
    horizon: value.horizon as GoalHorizon,
    id: value.entry_id,
    relatedEntries,
    revision: value.revision,
    status: value.status as GoalStatus,
    tagNames: value.tag_names,
    targetDate: value.target_date,
    title: value.title,
    totalCount: value.total_count,
    updatedAt: value.updated_at,
  };
}

function parseRelatedEntries(value: unknown): GoalRelatedEntry[] | null {
  if (!Array.isArray(value)) return null;
  const entries: GoalRelatedEntry[] = [];
  for (const item of value) {
    if (
      !isRecord(item) ||
      typeof item.id !== "string" ||
      !nullableString(item.title) ||
      typeof item.body !== "string" ||
      !isWikiItemKind(item.item_kind) ||
      typeof item.item_subtype !== "string" ||
      !nullableString(item.occurred_start) ||
      !nullableString(item.occurred_label) ||
      !nullableString(item.occurred_timezone) ||
      typeof item.revision !== "number" ||
      typeof item.updated_at !== "string" ||
      typeof item.relationship !== "string"
    ) {
      return null;
    }
    entries.push({
      body: item.body,
      id: item.id,
      itemKind: item.item_kind,
      itemSubtype: item.item_subtype,
      occurredLabel: item.occurred_label,
      occurredStart: item.occurred_start,
      occurredTimezone: item.occurred_timezone,
      relationship: item.relationship,
      revision: item.revision,
      title: item.title || "Untitled Entry",
      updatedAt: item.updated_at,
    });
  }
  return entries;
}

function parseAttachments(value: unknown): GoalAttachment[] | null {
  if (!Array.isArray(value)) return null;
  const attachments: GoalAttachment[] = [];
  for (const item of value) {
    if (
      !isRecord(item) ||
      typeof item.id !== "string" ||
      typeof item.bucket_id !== "string" ||
      typeof item.object_path !== "string" ||
      !nullableString(item.original_filename) ||
      typeof item.mime_type !== "string" ||
      !firstTimeImageMimeTypes.includes(
        item.mime_type as FirstTimeImageMimeType,
      ) ||
      !nullableNumber(item.byte_size) ||
      !nullableNumber(item.pixel_width) ||
      !nullableNumber(item.pixel_height) ||
      typeof item.created_at !== "string"
    ) {
      return null;
    }
    attachments.push({
      bucketId: item.bucket_id,
      byteSize: item.byte_size,
      createdAt: item.created_at,
      id: item.id,
      imageUrl: null,
      mimeType: item.mime_type as FirstTimeImageMimeType,
      objectPath: item.object_path,
      originalFilename: item.original_filename,
      pixelHeight: item.pixel_height,
      pixelWidth: item.pixel_width,
    });
  }
  return attachments;
}

function nullableString(value: unknown) {
  return value === null || typeof value === "string";
}

function entryOptionTitle(title: string | null, body: string | null) {
  const normalizedTitle = title?.trim();
  if (normalizedTitle) return normalizedTitle;
  const normalizedBody = body?.trim();
  if (!normalizedBody) return "Untitled Entry";
  return normalizedBody.length > 80
    ? `${normalizedBody.slice(0, 80).trimEnd()}...`
    : normalizedBody;
}

function nullableNumber(value: unknown): value is number | null {
  return (
    value === null || (typeof value === "number" && Number.isFinite(value))
  );
}

function stringArray(value: unknown): value is string[] {
  return (
    Array.isArray(value) && value.every((item) => typeof item === "string")
  );
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}
