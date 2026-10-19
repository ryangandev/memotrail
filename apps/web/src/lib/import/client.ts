import type { ImportAction } from "./contracts";

export class ImportRequestError extends Error {
  constructor(
    public code: string,
    message: string,
    public status: number,
  ) {
    super(message);
  }
}

/** One call to the import route. The server says in plain words what went wrong. */
export async function importRequest<T>(
  action: ImportAction,
  signal?: AbortSignal,
): Promise<T> {
  let response: Response;
  try {
    response = await fetch("/api/import", {
      body: JSON.stringify(action),
      cache: "no-store",
      headers: { "content-type": "application/json" },
      method: "POST",
      signal,
    });
  } catch (error) {
    if (signal?.aborted) throw error;
    throw new ImportRequestError(
      "offline",
      "MemoTrail could not be reached. Check your connection.",
      0,
    );
  }
  if (!response.ok) {
    const result = await response.json().catch(() => ({}));
    throw new ImportRequestError(
      result.code ?? "unavailable",
      result.error ?? "Import is unavailable. Try again.",
      response.status,
    );
  }
  return (await response.json()) as T;
}

/** Saves the CSV report of what was not imported. */
export async function downloadImportReport(jobId: string) {
  const response = await fetch("/api/import", {
    body: JSON.stringify({ action: "report", jobId }),
    cache: "no-store",
    headers: { "content-type": "application/json" },
    method: "POST",
  });
  if (!response.ok)
    throw new ImportRequestError(
      "unavailable",
      "The report could not be created.",
      response.status,
    );
  const url = URL.createObjectURL(await response.blob());
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = `memotrail-import-report-${jobId.slice(0, 8)}.csv`;
  document.body.append(anchor);
  anchor.click();
  anchor.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 60_000);
}
