import { validTimezone } from "@/lib/data/occurrence";
import {
  isImportSource,
  type ImportJobStatus,
  type ImportOptions,
  type ImportScanTotals,
  type ImportSource,
} from "./types";
import { importLabels } from "./labels";

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export type ImportAction =
  | { action: "state" }
  | { action: "create"; source: ImportSource; fileName: string; fileBytes: number }
  | { action: "scan"; jobId: string }
  | {
      action: "preview";
      jobId: string;
      warningsOnly: boolean;
      timezone: string | null;
    }
  | {
      action: "confirm";
      jobId: string;
      options: ImportOptions;
      excludedFolders: string[][];
    }
  | { action: "run"; jobId: string }
  | { action: "cancel"; jobId: string }
  | { action: "retry"; jobId: string }
  | { action: "undo"; jobId: string }
  | { action: "report"; jobId: string }
  | { action: "cleanup" };

function record(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

export function parseImportOptions(value: unknown): ImportOptions | null {
  const input = record(value);
  const tags = record(input?.tags);
  if (!input || !tags) return null;
  if (
    typeof input.timezone !== "string" ||
    !validTimezone(input.timezone) ||
    (input.undated !== "leave" && input.undated !== "file_time") ||
    ![tags.source, tags.folders, tags.properties, tags.marker].every(
      (flag) => typeof flag === "boolean",
    )
  )
    return null;
  const property = input.notionDateProperty;
  if (
    property !== null &&
    property !== undefined &&
    (typeof property !== "string" || property.length > 100)
  )
    return null;
  return {
    notionDateProperty: typeof property === "string" ? property : null,
    tags: {
      folders: tags.folders as boolean,
      marker: tags.marker as boolean,
      properties: tags.properties as boolean,
      source: tags.source as boolean,
    },
    timezone: input.timezone,
    undated: input.undated,
  };
}

/** Folders to leave out: arrays of folder names, at most 2,000 of them. */
function parseFolders(value: unknown): string[][] | null {
  if (value === undefined) return [];
  if (!Array.isArray(value) || value.length > 2_000) return null;
  const folders: string[][] = [];
  for (const folder of value) {
    if (
      !Array.isArray(folder) ||
      folder.length === 0 ||
      folder.length > 40 ||
      !folder.every((name) => typeof name === "string" && name.length <= 300)
    )
      return null;
    folders.push(folder as string[]);
  }
  return folders;
}

export function parseImportAction(value: unknown): ImportAction | null {
  const input = record(value);
  if (!input || typeof input.action !== "string") return null;
  const jobId =
    typeof input.jobId === "string" && uuid.test(input.jobId) ? input.jobId : null;
  switch (input.action) {
    case "state":
    case "cleanup":
      return { action: input.action };
    case "create": {
      if (
        !isImportSource(input.source) ||
        typeof input.fileName !== "string" ||
        input.fileName.length > 255 ||
        typeof input.fileBytes !== "number" ||
        !Number.isSafeInteger(input.fileBytes) ||
        input.fileBytes < 1
      )
        return null;
      return {
        action: "create",
        fileBytes: input.fileBytes,
        fileName: input.fileName,
        source: input.source,
      };
    }
    case "confirm": {
      const options = parseImportOptions(input.options);
      const excludedFolders = parseFolders(input.excludedFolders);
      return jobId && options && excludedFolders
        ? { action: "confirm", excludedFolders, jobId, options }
        : null;
    }
    case "preview":
      return jobId
        ? {
            action: "preview",
            jobId,
            timezone:
              typeof input.timezone === "string" && validTimezone(input.timezone)
                ? input.timezone
                : null,
            warningsOnly: input.warningsOnly === true,
          }
        : null;
    case "scan":
    case "run":
    case "cancel":
    case "retry":
    case "undo":
    case "report":
      return jobId ? { action: input.action, jobId } : null;
    default:
      return null;
  }
}

export type ImportJobView = {
  id: string;
  source: ImportSource;
  status: ImportJobStatus;
  fileName: string | null;
  fileBytes: number | null;
  errorCode: string | null;
  totals: Partial<ImportScanTotals> & {
    overlap?: { unchanged: number; changed: number; inTrash: number };
  };
  options: Partial<ImportOptions>;
  createdAt: string;
  finishedAt: string | null;
  /** Whether the staged ZIP is still there, which is what a retry needs. */
  staged: boolean;
};

export type ImportProgress = {
  status: ImportJobStatus;
  items: Partial<Record<string, number>>;
  reasons: Partial<Record<string, number>>;
  photos: { imported: number; failed: number; skipped: number };
  finished_at: string | null;
};

export type ImportSample = {
  sourceKey: string;
  folderPath: string[];
  title: string | null;
  text: string;
  dateLabel: string;
  tagNames: string[];
  photoCount: number;
  warnings: string[];
};

export function importErrorMessage(code: string | null | undefined): string {
  switch (code) {
    case "unsupported_archive":
      return "This is not a ZIP file MemoTrail can read. Export again and upload the ZIP as the app made it.";
    case "encrypted_archive":
      return "This ZIP is password protected, which MemoTrail cannot open. Export again without a password.";
    case "too_many_files":
      return "This ZIP has too many files. Export fewer notes at a time.";
    case "archive_too_large":
    case "compression_ratio":
      return "The contents of this ZIP are larger than MemoTrail can read. Export fewer notes at a time.";
    case "too_large":
      return "This ZIP is larger than the import limit. Export fewer notes at a time.";
    case "too_many_entries":
      return "This export has more notes than one import can hold. Export fewer notes at a time.";
    case "too_many_photos":
      return "This export has more photos than one import can hold. Export fewer notes at a time.";
    case "empty_import":
      return "No notes MemoTrail can import were found in this ZIP. Check that you chose the right app.";
    case "storage_unavailable":
      return "The uploaded file could not be found. Choose the file and upload it again.";
    case "storage_full":
      return "MemoTrail ran out of storage space. Free some space and continue the import.";
    case "expired":
      return "This import was left for a day and has ended. Nothing was imported after that point.";
    default:
      return "The import stopped unexpectedly. Your library is unchanged by anything that did not finish. Try again.";
  }
}

export function importResultReasonLabel(reason: string): string {
  return importLabels.reasons[reason] ?? "Not imported";
}
