"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { notify } from "@/components/app-toast";
import { Button } from "@/components/button";
import { useConfirmationDialog } from "@/components/confirmation-dialog";
import { ImportPreview } from "@/components/import-preview";
import { ImportResult } from "@/components/import-result";
import { ImportStart } from "@/components/import-start";
import { PageFrame } from "@/components/page-frame";
import { PageHeader } from "@/components/page-header";
import { countLabel } from "@/lib/count-label";
import {
  importErrorMessage,
  type ImportJobView,
  type ImportProgress,
} from "@/lib/import/contracts";
import {
  ImportRequestError,
  downloadImportReport,
  importRequest,
} from "@/lib/import/client";
import { sourceLabel } from "@/lib/import/labels";
import { formatBytes } from "@/lib/import/sources";
import { UploadFailedError, uploadStagedZip } from "@/lib/import/upload";
import type { ImportOptions, ImportSource } from "@/lib/import/types";
import styles from "@/components/import-workspace.module.css";

type StateResponse = {
  job: ImportJobView | null;
  progress: ImportProgress | null;
};
type RunResponse = {
  progress: ImportProgress | null;
  run: { kind: "busy" | "more" | "finished" | "paused_quota" | "stopped" };
};

const sleep = (ms: number, signal: AbortSignal) =>
  new Promise<void>((resolve) => {
    const timer = window.setTimeout(resolve, ms);
    signal.addEventListener("abort", () => {
      window.clearTimeout(timer);
      resolve();
    });
  });

const finished = ["completed", "completed_with_issues"];

function messageOf(error: unknown, fallback: string) {
  return error instanceof Error && error.message ? error.message : fallback;
}

export function ImportWorkspace({
  availableSources,
  initialError,
  initialJob,
  initialProgress,
  maxBytes,
}: {
  availableSources: ImportSource[];
  initialError: boolean;
  initialJob: ImportJobView | null;
  initialProgress: ImportProgress | null;
  maxBytes: number;
}) {
  const confirm = useConfirmationDialog();
  const [job, setJob] = useState(initialJob);
  const [progress, setProgress] = useState(initialProgress);
  const [dismissed, setDismissed] = useState(false);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState(
    initialError ? "Import could not load. Refresh to try again." : "",
  );
  const [upload, setUpload] = useState<{ sent: number; total: number } | null>(
    null,
  );
  const [runProblem, setRunProblem] = useState("");
  const [runKey, setRunKey] = useState(0);
  const uploading = useRef<AbortController | null>(null);
  const scanning = useRef(false);
  const resumeInput = useRef<HTMLInputElement>(null);

  const refresh = useCallback(async () => {
    const state = await importRequest<StateResponse>({ action: "state" });
    setJob(state.job);
    setProgress(state.progress);
    return state;
  }, []);

  // Staged files of imports that ended are removed whenever this page opens.
  useEffect(() => {
    void importRequest({ action: "cleanup" }).catch(() => undefined);
  }, []);

  useEffect(
    () => () => {
      uploading.current?.abort();
    },
    [],
  );

  const scan = useCallback(
    async (jobId: string) => {
      if (scanning.current) return;
      scanning.current = true;
      try {
        const result = await importRequest<{ job: ImportJobView }>({
          action: "scan",
          jobId,
        });
        setJob(result.job);
      } catch (error) {
        setMessage(messageOf(error, "The export could not be read."));
        await refresh().catch(() => undefined);
      } finally {
        scanning.current = false;
      }
    },
    [refresh],
  );

  // A reload in the middle of reading continues reading.
  useEffect(() => {
    if (job?.status !== "scanning") return;
    const jobId = job.id;
    const timer = window.setTimeout(() => void scan(jobId), 0);
    return () => window.clearTimeout(timer);
  }, [job?.id, job?.status, scan]);

  // The run loop: each call works for most of its time limit and asks to be called again.
  useEffect(() => {
    if (job?.status !== "running") return;
    const jobId = job.id;
    const controller = new AbortController();
    const { signal } = controller;
    void (async () => {
      let failures = 0;
      while (!signal.aborted) {
        try {
          const result = await importRequest<RunResponse>(
            { action: "run", jobId },
            signal,
          );
          failures = 0;
          if (result.progress) setProgress(result.progress);
          const kind = result.run.kind;
          if (kind === "finished" || kind === "paused_quota") {
            await refresh();
            return;
          }
          if (kind === "busy" || kind === "stopped") {
            await sleep(4000, signal);
            const state = await refresh();
            if (state.job?.status !== "running") return;
          }
        } catch (error) {
          if (signal.aborted) return;
          failures += 1;
          const final =
            error instanceof ImportRequestError &&
            error.status >= 400 &&
            error.status < 500 &&
            error.status !== 408 &&
            error.status !== 429;
          if (final || failures >= 5) {
            setRunProblem(messageOf(error, "The import lost its connection."));
            return;
          }
          await sleep(2000 * failures, signal);
        }
      }
    })();
    // Progress arrives while a long call is still working.
    const poll = window.setInterval(() => {
      void importRequest<StateResponse>({ action: "state" }, signal).then(
        (state) => {
          if (signal.aborted) return;
          setProgress(state.progress);
          if (state.job && state.job.status !== "running") setJob(state.job);
        },
        () => undefined,
      );
    }, 3000);
    return () => {
      controller.abort();
      window.clearInterval(poll);
    };
  }, [job?.id, job?.status, refresh, runKey]);

  async function uploadAndScan(target: ImportJobView, file: File) {
    if (!target.stagingPath) return;
    const controller = new AbortController();
    uploading.current = controller;
    setUpload({ sent: 0, total: file.size });
    try {
      await uploadStagedZip({
        file,
        objectName: target.stagingPath,
        onProgress: (sent, total) => setUpload({ sent, total }),
        signal: controller.signal,
      });
    } catch (error) {
      if (error instanceof DOMException && error.name === "AbortError") return;
      setMessage(
        error instanceof UploadFailedError
          ? error.message
          : "The upload failed. Choose the same file to continue.",
      );
      return;
    } finally {
      uploading.current = null;
      setUpload(null);
    }
    setJob((current) =>
      current ? { ...current, status: "scanning" } : current,
    );
    await scan(target.id);
  }

  async function begin(file: File, source: ImportSource) {
    setBusy(true);
    setMessage("");
    try {
      const created = await importRequest<{
        jobId: string;
        stagingPath: string;
      }>({
        action: "create",
        fileBytes: file.size,
        fileName: file.name,
        source,
      });
      const next: ImportJobView = {
        createdAt: new Date().toISOString(),
        errorCode: null,
        fileBytes: file.size,
        fileName: file.name,
        finishedAt: null,
        id: created.jobId,
        options: {},
        source,
        staged: true,
        stagingPath: created.stagingPath,
        status: "uploading",
        totals: {},
      };
      setDismissed(false);
      setProgress(null);
      setJob(next);
      setBusy(false);
      await uploadAndScan(next, file);
    } catch (error) {
      setMessage(messageOf(error, "The import could not start."));
    } finally {
      setBusy(false);
    }
  }

  async function continueUpload(file: File | undefined) {
    if (!file || !job) return;
    if (file.size !== job.fileBytes) {
      setMessage(
        `That is not the same file. Choose ${job.fileName} (${formatBytes(job.fileBytes ?? 0)}) to continue.`,
      );
      return;
    }
    setMessage("");
    await uploadAndScan(job, file);
  }

  async function act<T>(
    task: () => Promise<T>,
    failure: string,
  ): Promise<T | undefined> {
    setBusy(true);
    setMessage("");
    try {
      return await task();
    } catch (error) {
      setMessage(messageOf(error, failure));
      return undefined;
    } finally {
      setBusy(false);
    }
  }

  async function startImport(
    options: ImportOptions,
    excludedFolders: string[][],
  ) {
    if (!job) return;
    const jobId = job.id;
    const result = await act(
      () =>
        importRequest({ action: "confirm", excludedFolders, jobId, options }),
      "The import could not start.",
    );
    if (result) {
      setRunProblem("");
      await refresh().catch(() => undefined);
    }
  }

  async function cancel() {
    if (!job) return;
    const jobId = job.id;
    const ok = await confirm({
      confirmLabel: "Cancel import",
      cancelLabel: "Keep going",
      description:
        job.status === "running"
          ? "Entries already imported stay in your Library. You can undo them from the result."
          : "Nothing has been added to your Library.",
      title: "Cancel this import?",
      variant: "danger",
    });
    if (!ok) return;
    uploading.current?.abort();
    const result = await act(
      () => importRequest({ action: "cancel", jobId }),
      "The import could not be cancelled.",
    );
    if (result) await refresh().catch(() => undefined);
  }

  async function retry() {
    if (!job) return;
    const jobId = job.id;
    const result = await act(
      () => importRequest({ action: "retry", jobId }),
      "The retry could not start.",
    );
    if (result) await refresh().catch(() => undefined);
  }

  async function undo() {
    if (!job) return;
    const jobId = job.id;
    const ok = await confirm({
      confirmLabel: "Move to Trash",
      description:
        "The Entries from this import move to Trash, where you can restore them for 30 days. Entries you have edited since are left in your Library.",
      title: "Undo this import?",
      variant: "danger",
    });
    if (!ok) return;
    const result = await act(
      () =>
        importRequest<{ trashed: number; edited: number }>({
          action: "undo",
          jobId,
        }),
      "The import could not be undone.",
    );
    if (!result) return;
    notify.success(
      result.edited > 0
        ? `${countLabel(result.trashed, "Entry")} moved to Trash. ${result.edited} you edited stayed in your Library.`
        : `${countLabel(result.trashed, "Entry")} moved to Trash.`,
    );
    await refresh().catch(() => undefined);
  }

  async function report() {
    if (!job) return;
    const jobId = job.id;
    await act(
      () => downloadImportReport(jobId),
      "The report could not be created.",
    );
  }

  const status = job?.status;
  const showResult = Boolean(
    job && status && finished.includes(status) && !dismissed,
  );
  const active =
    job &&
    status &&
    [
      "uploading",
      "scanning",
      "preview_ready",
      "running",
      "paused_quota",
    ].includes(status);
  const ended =
    job && status && ["failed", "expired"].includes(status) && !dismissed
      ? importErrorMessage(status === "expired" ? "expired" : job.errorCode)
      : "";

  return (
    <PageFrame className={styles.content} variant="compact">
      <PageHeader
        title={<>Import</>}
        eyebrow={<>BRING YOUR NOTES HERE</>}
        description={
          <>
            Move a journal or notes from another app into MemoTrail as ordinary
            Entries. No AI processing.
          </>
        }
      />
      {message ? (
        <p className={styles.notice} data-tone="danger" role="alert">
          {message}
        </p>
      ) : null}
      {ended ? (
        <p className={styles.notice} data-tone="warning" role="status">
          {ended}
        </p>
      ) : null}

      {!active && !showResult ? (
        <ImportStart
          availableSources={availableSources}
          busy={busy}
          maxBytes={maxBytes}
          onChoose={(file, source) => void begin(file, source)}
        />
      ) : null}

      {job && status === "uploading" ? (
        <section aria-labelledby="import-upload" className={styles.card}>
          <h2 id="import-upload">Uploading {job.fileName}</h2>
          {upload ? (
            <div className={styles.progress}>
              <progress max={upload.total} value={upload.sent} />
              <div className={styles.progressText}>
                <span>
                  {formatBytes(upload.sent)} of {formatBytes(upload.total)}
                </span>
                <span>{Math.floor((upload.sent / upload.total) * 100)}%</span>
              </div>
              <p>
                Keep this tab open until the upload is done. If the connection
                drops, choose the same file again and it continues.
              </p>
            </div>
          ) : (
            <>
              <p>
                This upload did not finish. Choose {job.fileName} again and it
                continues where it stopped.
              </p>
              <div className={styles.actions}>
                <input
                  accept=".zip,application/zip,application/x-zip-compressed"
                  aria-label="Choose the same ZIP file"
                  className={styles.fileInput}
                  onChange={(event) => {
                    void continueUpload(event.target.files?.[0]);
                    event.target.value = "";
                  }}
                  ref={resumeInput}
                  tabIndex={-1}
                  type="file"
                />
                <Button
                  onClick={() => resumeInput.current?.click()}
                  variant="primary"
                >
                  Choose {job.fileName}
                </Button>
              </div>
            </>
          )}
          <div className={styles.actions}>
            <Button
              disabled={busy}
              onClick={() => void cancel()}
              variant="secondary"
            >
              Cancel
            </Button>
          </div>
        </section>
      ) : null}

      {job && status === "scanning" ? (
        <section className={styles.card} aria-live="polite">
          <h2>Reading your export</h2>
          <p>
            Looking through {job.fileName} to see what can be imported. Nothing
            is added to your Library yet. This can take a minute for a large
            export.
          </p>
        </section>
      ) : null}

      {job && status === "preview_ready" ? (
        <ImportPreview
          busy={busy}
          job={job}
          onCancel={() => void cancel()}
          onConfirm={(options, excluded) => void startImport(options, excluded)}
        />
      ) : null}

      {job && (status === "running" || status === "paused_quota") ? (
        <RunPanel
          busy={busy}
          job={job}
          onCancel={() => void cancel()}
          onResume={() => {
            setRunProblem("");
            setJob((current) =>
              current ? { ...current, status: "running" } : current,
            );
            setRunKey((key) => key + 1);
          }}
          problem={runProblem}
          progress={progress}
        />
      ) : null}

      {job && showResult ? (
        <ImportResult
          busy={busy}
          job={job}
          onDone={() => setDismissed(true)}
          onReport={() => void report()}
          onRetry={() => void retry()}
          onUndo={() => void undo()}
          progress={progress}
        />
      ) : null}
    </PageFrame>
  );
}

function RunPanel({
  busy,
  job,
  onCancel,
  onResume,
  problem,
  progress,
}: {
  busy: boolean;
  job: ImportJobView;
  onCancel: () => void;
  onResume: () => void;
  problem: string;
  progress: ImportProgress | null;
}) {
  const items = progress?.items ?? {};
  const total = Object.values(items).reduce<number>(
    (sum, count) => sum + (count ?? 0),
    0,
  );
  const waiting = (items.pending ?? 0) + (items.photos_pending ?? 0);
  const done = Math.max(0, total - waiting);
  const paused = job.status === "paused_quota";

  return (
    <section aria-labelledby="import-running" className={styles.card}>
      <h2 id="import-running">
        {paused ? "Import paused" : `Importing from ${sourceLabel(job.source)}`}
      </h2>
      {paused ? (
        <p className={styles.notice} data-tone="warning" role="status">
          {importErrorMessage("storage_full")}
        </p>
      ) : (
        <p>
          Keep this tab open. If you close it, come back to Settings, then
          Import, and it continues where it stopped.
        </p>
      )}
      <div className={styles.progress} aria-live="polite">
        <progress max={Math.max(total, 1)} value={done} />
        <div className={styles.progressText}>
          <span>
            {done} of {countLabel(total, "Entry")}
          </span>
          {progress?.photos?.imported ? (
            <span>{countLabel(progress.photos.imported, "photo")} added</span>
          ) : null}
        </div>
      </div>
      {problem ? (
        <p className={styles.notice} data-tone="danger" role="alert">
          {problem}
        </p>
      ) : null}
      <div className={styles.actions}>
        {paused || problem ? (
          <Button disabled={busy} onClick={onResume} variant="primary">
            Continue import
          </Button>
        ) : null}
        <Button disabled={busy} onClick={onCancel} variant="secondary">
          Cancel import
        </Button>
      </div>
    </section>
  );
}
