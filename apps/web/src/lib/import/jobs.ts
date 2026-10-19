import type { SupabaseClient } from "@supabase/supabase-js";
import { occurrenceLabel, validTimezone } from "@/lib/data/occurrence";
import { plainTextFromDocument } from "@/lib/data/rich-text";
import {
  importErrorMessage,
  type ImportAction,
  type ImportJobView,
  type ImportProgress,
  type ImportSample,
} from "./contracts";
import { resolveImportDate } from "./dates";
import { archivePhotoReader, supabaseGateway } from "./gateway";
import { importLimits, importMaxZipBytes } from "./limits";
import { runImport } from "./run";
import { scanArchive, type ImportPayload, type ScanRow } from "./scan";
import { openStagedArchive, removeStagedFiles } from "./storage";
import { defaultImportOptions } from "./tags";
import { ImportError } from "./zip";
import type { ImportJobStatus, ImportSource } from "./types";

export class ImportApiError extends Error {
  constructor(
    public code: string,
    public status: number,
    message?: string,
  ) {
    super(message ?? importErrorMessage(code));
  }
}

export type ImportActionResult =
  | { kind: "json"; body: unknown }
  | { kind: "csv"; filename: string; body: string };

type JobRow = {
  id: string;
  source: ImportSource;
  status: ImportJobStatus;
  file_name: string | null;
  file_bytes: number | null;
  staging_path: string | null;
  options: ImportJobView["options"];
  totals: ImportJobView["totals"];
  error_code: string | null;
  created_at: string;
  finished_at: string | null;
};

const jobColumns =
  "id,source,status,file_name,file_bytes,staging_path,options,totals,error_code,created_at,finished_at";

function view(row: JobRow): ImportJobView {
  return {
    createdAt: row.created_at,
    errorCode: row.error_code,
    fileBytes: row.file_bytes,
    fileName: row.file_name,
    finishedAt: row.finished_at,
    id: row.id,
    options: row.options ?? {},
    source: row.source,
    staged: row.staging_path !== null,
    stagingPath: row.status === "uploading" ? row.staging_path : null,
    status: row.status,
    totals: row.totals ?? {},
  };
}

async function loadJobRow(
  client: SupabaseClient,
  jobId: string,
): Promise<JobRow> {
  const { data, error } = await client
    .from("import_jobs")
    .select(jobColumns)
    .eq("id", jobId)
    .maybeSingle();
  if (error) throw new ImportApiError("unavailable", 503);
  if (!data)
    throw new ImportApiError("not_found", 404, "This import was not found.");
  return data as unknown as JobRow;
}

/** The most recent import, which is the one the page picks up where it left off. */
export async function latestJobView(
  client: SupabaseClient,
): Promise<ImportJobView | null> {
  const { data, error } = await client
    .from("import_jobs")
    .select(jobColumns)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (error) throw new ImportApiError("unavailable", 503);
  return data ? view(data as unknown as JobRow) : null;
}

export async function progressOf(
  client: SupabaseClient,
  jobId: string,
): Promise<ImportProgress | null> {
  const { data, error } = await client.rpc("import_job_progress", {
    p_job_id: jobId,
  });
  if (error) throw new ImportApiError("unavailable", 503);
  return (data as ImportProgress | null) ?? null;
}

async function profileTimezone(client: SupabaseClient, ownerId: string) {
  const { data } = await client
    .from("profiles")
    .select("timezone")
    .eq("user_id", ownerId)
    .maybeSingle();
  const zone = (data as { timezone?: string } | null)?.timezone;
  return zone && validTimezone(zone) ? zone : "UTC";
}

async function transition(
  client: SupabaseClient,
  jobId: string,
  from: ImportJobStatus[],
  to: string,
  patch: Record<string, unknown> = {},
) {
  const { data, error } = await client.rpc("update_import_job", {
    p_from: from,
    p_job_id: jobId,
    p_patch: patch,
    p_status: to,
  });
  if (error) throw new ImportApiError("unavailable", 503);
  return typeof data === "string" ? data : null;
}

export async function createJob(
  client: SupabaseClient,
  input: Extract<ImportAction, { action: "create" }>,
) {
  const maxBytes = importMaxZipBytes();
  if (input.fileBytes > maxBytes) throw new ImportApiError("too_large", 413);
  const { data, error } = await client.rpc("create_import_job", {
    p_file_bytes: input.fileBytes,
    p_file_name: input.fileName,
    p_source: input.source,
  });
  if (error) {
    if (error.message?.includes("import_job_active"))
      throw new ImportApiError(
        "import_job_active",
        409,
        "Another import is still open. Finish or cancel it first.",
      );
    throw new ImportApiError("unavailable", 503);
  }
  const row = (Array.isArray(data) ? data[0] : data) as
    { job_id: string; staging_path: string } | undefined;
  if (!row) throw new ImportApiError("unavailable", 503);
  return { jobId: row.job_id, maxBytes, stagingPath: row.staging_path };
}

export async function scanJob(
  client: SupabaseClient,
  ownerId: string,
  jobId: string,
): Promise<ImportJobView> {
  const row = await loadJobRow(client, jobId);
  if (!["uploading", "scanning"].includes(row.status)) return view(row);
  if (!row.staging_path) throw new ImportApiError("storage_unavailable", 409);
  if (!(await transition(client, jobId, ["uploading", "scanning"], "scanning")))
    throw new ImportApiError("unavailable", 409);

  const timezone = await profileTimezone(client, ownerId);
  let archive;
  try {
    const opened = await openStagedArchive(client, row.staging_path);
    archive = opened.archive;
    const totals = await scanArchive(
      archive,
      { source: row.source, timezone },
      {
        async add(rows: ScanRow[]) {
          const { data, error } = await client.rpc("add_import_items", {
            p_items: rows,
            p_job_id: jobId,
          });
          if (error) throw new Error("add_import_items");
          return Number(data ?? 0);
        },
      },
    );
    await transition(client, jobId, ["scanning"], "preview_ready", {
      file_bytes: opened.size,
      totals,
    });
  } catch (error) {
    const code = error instanceof ImportError ? error.code : "unexpected";
    await transition(client, jobId, ["scanning"], "failed", {
      error_code: code,
    });
  } finally {
    archive?.close();
  }
  return view(await loadJobRow(client, jobId));
}

function sampleOf(
  row: {
    source_key: string;
    folder_path: string[];
    payload: ImportPayload;
    media: { photos?: unknown[] } | null;
  },
  timezone: string,
): ImportSample {
  const payload = row.payload;
  const resolved = resolveImportDate(payload.date, {
    fileModifiedAt: null,
    timezone,
    undated: "leave",
  });
  const text = plainTextFromDocument(payload.bodyRich);
  return {
    dateLabel: occurrenceLabel({
      datePrecision: resolved.datePrecision,
      occurredAt: resolved.occurredStart,
      occurredEnd: resolved.occurredEnd,
      occurredLabel: resolved.occurredLabel,
      occurredTimezone: resolved.occurredTimezone,
    }),
    folderPath: row.folder_path,
    photoCount: row.media?.photos?.length ?? 0,
    sourceKey: row.source_key,
    tagNames: [...payload.tagNames, ...payload.propertyTagNames].slice(0, 6),
    text: text.length > 280 ? `${text.slice(0, 280)}...` : text,
    title: payload.title,
    warnings: payload.warnings,
  };
}

export async function previewJob(
  client: SupabaseClient,
  ownerId: string,
  input: Extract<ImportAction, { action: "preview" }>,
) {
  const row = await loadJobRow(client, input.jobId);
  const timezone = input.timezone ?? (await profileTimezone(client, ownerId));
  const [sample, overlap] = await Promise.all([
    client.rpc("import_job_sample", {
      p_job_id: input.jobId,
      p_limit: importLimits.sampleEntries,
      p_warnings_only: input.warningsOnly,
    }),
    client.rpc("import_job_overlap", { p_job_id: input.jobId }),
  ]);
  if (sample.error || overlap.error)
    throw new ImportApiError("unavailable", 503);
  const overlapRow = (
    overlap.data as { unchanged: number; changed: number; in_trash: number }[]
  )?.[0];
  const job = view(row);
  return {
    defaults: defaultImportOptions(timezone, {
      distinctParentFolders: job.totals.distinctParentFolders ?? 0,
      notionDateProperty: job.totals.notionDateProperty ?? null,
    }),
    job: {
      ...job,
      totals: {
        ...job.totals,
        overlap: {
          changed: Number(overlapRow?.changed ?? 0),
          inTrash: Number(overlapRow?.in_trash ?? 0),
          unchanged: Number(overlapRow?.unchanged ?? 0),
        },
      },
    },
    sample: (sample.data as Parameters<typeof sampleOf>[0][]).map((entry) =>
      sampleOf(entry, timezone),
    ),
  };
}

export async function confirmJob(
  client: SupabaseClient,
  input: Extract<ImportAction, { action: "confirm" }>,
) {
  const { data, error } = await client.rpc("confirm_import_job", {
    p_excluded_folders: input.excludedFolders,
    p_job_id: input.jobId,
    p_options: input.options,
  });
  if (error) {
    if (error.message?.includes("import_job_not_ready"))
      throw new ImportApiError(
        "not_ready",
        409,
        "This import is not ready to start.",
      );
    throw new ImportApiError("unavailable", 503);
  }
  return { selected: Number(data ?? 0) };
}

export async function runJob(
  client: SupabaseClient,
  ownerId: string,
  jobId: string,
) {
  const row = await loadJobRow(client, jobId);
  if (!["running", "paused_quota"].includes(row.status))
    return {
      progress: await progressOf(client, jobId),
      run: { kind: "stopped" as const },
    };
  if (!row.staging_path) throw new ImportApiError("storage_unavailable", 409);
  const options = defaultedOptions(row, await profileTimezone(client, ownerId));
  const { archive } = await openStagedArchive(client, row.staging_path);
  try {
    const run = await runImport({
      gateway: supabaseGateway(client, jobId),
      options,
      ownerId,
      photos: archivePhotoReader(archive, importLimits.maxPhotoBytes),
      source: row.source,
    });
    return { progress: await progressOf(client, jobId), run };
  } finally {
    archive.close();
  }
}

function defaultedOptions(row: JobRow, timezone: string) {
  const defaults = defaultImportOptions(timezone, {
    distinctParentFolders: 0,
    notionDateProperty: null,
  });
  return {
    ...defaults,
    ...row.options,
    tags: { ...defaults.tags, ...row.options.tags },
  };
}

export async function cancelJob(client: SupabaseClient, jobId: string) {
  const { data, error } = await client.rpc("cancel_import_job", {
    p_job_id: jobId,
  });
  if (error) throw new ImportApiError("unavailable", 503);
  await cleanupStaging(client);
  return { cancelled: data === true };
}

export async function retryJob(client: SupabaseClient, jobId: string) {
  const { data, error } = await client.rpc("retry_import_items", {
    p_job_id: jobId,
  });
  if (error) {
    if (error.message?.includes("import_job_not_retryable"))
      throw new ImportApiError(
        "not_retryable",
        409,
        "This import can no longer be retried. Import the file again to pick up what is missing.",
      );
    if (error.message?.includes("import_job_active"))
      throw new ImportApiError(
        "import_job_active",
        409,
        "Another import is still open.",
      );
    throw new ImportApiError("unavailable", 503);
  }
  return { retried: Number(data ?? 0) };
}

export async function undoJob(client: SupabaseClient, jobId: string) {
  const { data, error } = await client.rpc("trash_import_job", {
    p_job_id: jobId,
  });
  if (error) {
    if (error.message?.includes("import_undo_expired"))
      throw new ImportApiError(
        "undo_expired",
        409,
        "This import is more than 30 days old. Move its Entries to Trash from Library.",
      );
    throw new ImportApiError(
      "not_undoable",
      409,
      "This import cannot be undone.",
    );
  }
  const row = (Array.isArray(data) ? data[0] : data) as
    { trashed: number; edited: number } | undefined;
  return {
    edited: Number(row?.edited ?? 0),
    trashed: Number(row?.trashed ?? 0),
  };
}

function csvCell(value: string | null) {
  const text = value ?? "";
  // A spreadsheet runs a cell that starts like a formula.
  const safe = /^[=+\-@\t\r]/.test(text) ? `'${text}` : text;
  return /[",\n\r]/.test(safe) ? `"${safe.replaceAll('"', '""')}"` : safe;
}

/** Items that did not become new Entries, without any of the writing. */
export async function reportJob(client: SupabaseClient, jobId: string) {
  const { data, error } = await client
    .from("import_items")
    .select("source_key,status,reason,entry_id")
    .eq("job_id", jobId)
    .in("status", ["skipped", "failed", "partial", "unchanged"])
    .order("source_key")
    .limit(20_000);
  if (error) throw new ImportApiError("unavailable", 503);
  const lines = [["source", "status", "reason", "entry_id"].join(",")];
  for (const item of data as {
    source_key: string;
    status: string;
    reason: string | null;
    entry_id: string | null;
  }[])
    lines.push(
      [item.source_key, item.status, item.reason, item.entry_id]
        .map(csvCell)
        .join(","),
    );
  return lines.join("\n") + "\n";
}

/** Removes the staged ZIPs of imports that are over. */
export async function cleanupStaging(client: SupabaseClient) {
  const { data, error } = await client.rpc("expire_import_jobs");
  if (error) return { removed: 0 };
  const rows = (data ?? []) as { job_id: string; staging_path: string }[];
  const removedPaths = await removeStagedFiles(
    client,
    rows.map((row) => row.staging_path),
  );
  const jobIds = rows
    .filter((row) => removedPaths.includes(row.staging_path))
    .map((row) => row.job_id);
  if (jobIds.length > 0)
    await client.rpc("complete_import_staging_cleanup", { p_job_ids: jobIds });
  return { removed: jobIds.length };
}

export async function handleImportAction(
  client: SupabaseClient,
  ownerId: string,
  action: ImportAction,
): Promise<ImportActionResult> {
  const json = (body: unknown): ImportActionResult => ({ body, kind: "json" });
  switch (action.action) {
    case "state": {
      const job = await latestJobView(client);
      return json({
        job,
        maxBytes: importMaxZipBytes(),
        progress: job ? await progressOf(client, job.id) : null,
      });
    }
    case "create":
      return json(await createJob(client, action));
    case "scan":
      return json({ job: await scanJob(client, ownerId, action.jobId) });
    case "preview":
      return json(await previewJob(client, ownerId, action));
    case "confirm":
      return json(await confirmJob(client, action));
    case "run":
      return json(await runJob(client, ownerId, action.jobId));
    case "cancel":
      return json(await cancelJob(client, action.jobId));
    case "retry":
      return json(await retryJob(client, action.jobId));
    case "undo":
      return json(await undoJob(client, action.jobId));
    case "report":
      return {
        body: await reportJob(client, action.jobId),
        filename: `memotrail-import-report-${action.jobId.slice(0, 8)}.csv`,
        kind: "csv",
      };
    case "cleanup":
      return json(await cleanupStaging(client));
  }
}
