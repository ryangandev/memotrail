import type { RichTextDocument } from "@/lib/data/rich-text";

export const importSources = [
  "apple_journal",
  "apple_notes",
  "notion",
  "day_one",
  "markdown",
] as const;
export type ImportSource = (typeof importSources)[number];

export function isImportSource(value: unknown): value is ImportSource {
  return (
    typeof value === "string" &&
    (importSources as readonly string[]).includes(value)
  );
}

/**
 * When the source says something happened, with the precision it really has. A date with
 * no zone is kept as the local text the source showed, and is read in the time zone the
 * person chooses in the preview. Nothing here is ever made up: a source with no date is
 * unknown.
 */
export type ImportDate =
  | { precision: "exact"; instant: string; timezone?: string }
  | { precision: "exact"; local: string }
  | {
      precision: "day" | "month" | "year";
      local: string;
      timezone?: string;
    }
  | { precision: "range"; local: string; localEnd: string; timezone?: string }
  | { precision: "unknown"; label?: string };

/** A file inside the export that an Entry uses. */
export type ImportResource = {
  /** Stable within the candidate, so the attachment ID is the same on every retry. */
  key: string;
  /** The member path inside the (possibly nested) ZIP. */
  zipPath: string;
  /** The nested ZIP that holds the member, when the export is a ZIP of ZIPs. */
  container?: string;
  byteSize: number;
  originalFilename: string;
};

export type SkippedResource = { kind: string; count: number };

export type ImportCandidate = {
  source: ImportSource;
  sourceKey: string;
  /** Folders or notebooks the item sits in, for the preview tree and folder tags. */
  folderPath: string[];
  title: string | null;
  bodyRich: RichTextDocument;
  date: ImportDate;
  /** Tags the source itself carries (Day One tags, frontmatter, inline hashtags). */
  tagNames: string[];
  /** Tags from database properties, such as a Notion multi-select. */
  propertyTagNames: string[];
  locationLabel: string | null;
  photos: ImportResource[];
  skippedResources: SkippedResource[];
  sourceCreatedAt: string | null;
  sourceModifiedAt: string | null;
  /** A time taken from the file, shown only when the person asks for it. */
  fileModifiedAt: string | null;
  /** Stable codes such as date_unparsed, shown in the preview. */
  warnings: string[];
};

export const importWarnings = {
  dateUnparsed: "date_unparsed",
  bodySplit: "body_split",
  photoLimit: "photo_limit",
  photoTooLarge: "photo_too_large",
  photoMissing: "photo_missing",
  photoUnsupported: "photo_unsupported",
  tagsTrimmed: "tags_trimmed",
  titleShortened: "title_shortened",
} as const;

/** What the preview needs about each folder: the tree with counts. */
export type ImportFolderSummary = {
  path: string[];
  entries: number;
  photos: number;
};

/** Everything the preview shows, computed during the scan. */
export type ImportScanTotals = {
  entries: number;
  photos: number;
  photoBytes: number;
  undated: number;
  unparsedDates: number;
  dateRange: { from: string; to: string } | null;
  skippedResources: SkippedResource[];
  skippedItems: Record<string, number>;
  duplicateKeys: number;
  warnings: Record<string, number>;
  folders: ImportFolderSummary[];
  foldersTruncated: boolean;
  distinctParentFolders: number;
  detected: { source: ImportSource; confidence: number } | null;
  notionDateProperty: string | null;
  notionDateProperties: string[];
};

export type ImportOptions = {
  /** Zone for dates that carry none. */
  timezone: string;
  tags: {
    source: boolean;
    folders: boolean;
    properties: boolean;
    marker: boolean;
  };
  undated: "leave" | "file_time";
  notionDateProperty: string | null;
};

/** Where in the flow a person is. The job row holds the truth, so a reload resumes. */
export type ImportJobStatus =
  | "uploading"
  | "scanning"
  | "preview_ready"
  | "running"
  | "paused_quota"
  | "completed"
  | "completed_with_issues"
  | "failed"
  | "cancelled"
  | "expired";

export const activeImportStatuses: ImportJobStatus[] = [
  "uploading",
  "scanning",
  "preview_ready",
  "running",
  "paused_quota",
];

export type ImportItemStatus =
  | "pending"
  | "photos_pending"
  | "imported"
  | "unchanged"
  | "skipped"
  | "failed"
  | "partial";

/** One photo's progress, kept in the item's media. */
export type ImportPhotoState = {
  key: string;
  zipPath: string;
  container?: string;
  byteSize: number;
  originalFilename: string;
  status: "pending" | "done" | "failed" | "skipped";
  reason?: string;
};

export type ImportItemMedia = { photos: ImportPhotoState[] };
