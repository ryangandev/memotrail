"use client";
import { notify } from "@/components/app-toast";
import { PageHeader } from "@/components/page-header";
import { Button } from "@/components/button";
import { useEffect, useRef, useState } from "react";
import { PageFrame } from "@/components/page-frame";
import { SectionHeader } from "@/components/section-header";
import { SeparatedList } from "@/components/separated-list";
import {
  appendExportTail,
  exportFilename,
  hasCompleteExport,
  type ExportAction,
  type ExportSnapshot,
} from "@/lib/export/contracts";
import { countLabel } from "@/lib/count-label";
import styles from "@/components/export-settings.module.css";

type FileSink = {
  write(data: Uint8Array): Promise<void>;
  close(): Promise<void>;
  abort(): Promise<void>;
};
type PickerWindow = Window & {
  showSaveFilePicker?: (options: {
    suggestedName: string;
    types: { description: string; accept: Record<string, string[]> }[];
  }) => Promise<{ createWritable(): Promise<FileSink> }>;
};
class ExportRequestError extends Error {
  constructor(
    public code: string,
    message: string,
  ) {
    super(message);
  }
}
async function exportRequest(input: ExportAction, signal?: AbortSignal) {
  const response = await fetch("/api/export", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(input),
    signal,
    cache: "no-store",
  });
  if (!response.ok) {
    const result = await response.json();
    throw new ExportRequestError(
      result.code ?? "unavailable",
      result.error ?? "Export unavailable. Try again.",
    );
  }
  return response;
}
// Keep in step with the server's limit on unexpired exports.
const exportLimit = 2;

type Progress = { bytes: number | null; phase: "downloading" | "preparing" };

export function ExportSettings({
  initial,
  initialError,
  timezone,
}: {
  initial: ExportSnapshot[];
  initialError: boolean;
  // The time zone from Settings, so the server and browser show the same times.
  timezone: string;
}) {
  const [snapshots, setSnapshots] = useState<ExportSnapshot[]>(initial);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState(
    initialError ? "Could not load recent exports. Refresh to retry." : "",
  );
  const [progress, setProgress] = useState<Progress | null>(null);
  const [discard, setDiscard] = useState<ExportSnapshot | null>(null);
  // A retried export reuses its id, so a lost answer cannot make a second copy.
  const pendingCreate = useRef<string | null>(null);
  const active = useRef<AbortController | null>(null);
  useEffect(() => {
    return () => {
      active.current?.abort();
    };
  }, []);

  async function refresh(signal?: AbortSignal) {
    const response = await exportRequest({ action: "list" }, signal);
    const result = await response.json();
    setSnapshots(result.snapshots);
  }

  async function run(task: (controller: AbortController) => Promise<void>) {
    if (active.current) return;
    const controller = new AbortController();
    active.current = controller;
    setBusy(true);
    setMessage("");
    try {
      await task(controller);
    } finally {
      active.current = null;
      setBusy(false);
      setProgress(null);
    }
  }

  // Prepares a consistent copy of everything, then saves it as one ZIP.
  function exportEverything() {
    void run(async (controller) => {
      const id = (pendingCreate.current ??= crypto.randomUUID());
      let sink: FileSink | undefined;
      try {
        sink = await openSink({ captured_at: new Date().toISOString(), id });
      } catch {
        return;
      }
      let snapshot: ExportSnapshot;
      try {
        setProgress({ bytes: null, phase: "preparing" });
        const response = await exportRequest(
          { action: "create", id },
          controller.signal,
        );
        snapshot = (await response.json()).snapshot;
        pendingCreate.current = null;
        await refresh(controller.signal);
      } catch (error) {
        await sink?.abort().catch(() => {});
        if (
          error instanceof ExportRequestError &&
          ["expired", "request_unavailable"].includes(error.code)
        )
          pendingCreate.current = null;
        if (!controller.signal.aborted)
          setMessage(
            error instanceof Error
              ? error.message
              : "Could not prepare the export. Try again.",
          );
        return;
      }
      await save(snapshot, sink, controller);
    });
  }

  function downloadAgain(snapshot: ExportSnapshot) {
    void run(async (controller) => {
      let sink: FileSink | undefined;
      try {
        sink = await openSink(snapshot);
      } catch {
        return;
      }
      await save(snapshot, sink, controller);
    });
  }

  function discardSnapshot(snapshot: ExportSnapshot) {
    void run(async (controller) => {
      try {
        await exportRequest(
          { action: "discard", id: snapshot.id },
          controller.signal,
        );
        setDiscard(null);
        notify.success(
          "Export discarded. Your Entries and downloaded files are unchanged.",
        );
        await refresh(controller.signal);
      } catch (error) {
        if (!controller.signal.aborted)
          setMessage(
            error instanceof Error
              ? error.message
              : "Could not discard the export. Try again.",
          );
      }
    });
  }

  // Streams the ZIP to a chosen file where the browser allows it, otherwise to a download.
  async function save(
    snapshot: ExportSnapshot,
    sink: FileSink | undefined,
    controller: AbortController,
  ) {
    setProgress({ bytes: 0, phase: "downloading" });
    try {
      const response = await exportRequest(
        { action: "download", id: snapshot.id },
        controller.signal,
      );
      if (
        !response.body ||
        !response.headers.get("content-type")?.includes("application/zip")
      )
        throw new Error("Invalid export response.");
      const reader = response.body.getReader();
      const chunks: ArrayBuffer[] = [];
      let tail: Uint8Array = new Uint8Array(),
        received = 0;
      try {
        while (true) {
          const next = await reader.read();
          if (next.done) break;
          controller.signal.throwIfAborted();
          tail = appendExportTail(tail, next.value);
          received += next.value.byteLength;
          if (sink) await sink.write(next.value);
          else chunks.push(next.value.slice().buffer);
          setProgress({ bytes: received, phase: "downloading" });
        }
      } finally {
        reader.releaseLock();
      }
      if (!hasCompleteExport(tail)) throw new Error("Incomplete ZIP.");
      controller.signal.throwIfAborted();
      if (sink) {
        await sink.close();
        sink = undefined;
        notify.success("Export saved. Keep this private copy somewhere safe.");
      } else {
        const url = URL.createObjectURL(
          new Blob(chunks, { type: "application/zip" }),
        );
        const anchor = document.createElement("a");
        anchor.href = url;
        anchor.download = exportFilename(snapshot);
        document.body.append(anchor);
        anchor.click();
        anchor.remove();
        window.setTimeout(() => URL.revokeObjectURL(url), 60_000);
        notify.success(
          "Export ready. Check your browser downloads to finish saving it.",
        );
      }
    } catch (error) {
      controller.abort();
      await sink?.abort().catch(() => {});
      setMessage(
        error instanceof DOMException && error.name === "AbortError"
          ? "Download cancelled. You can download this export again below."
          : "The download did not complete, so no ZIP was saved. An original photo may be missing or changed, or the connection was interrupted. Download it again below, or export again.",
      );
    }
  }

  const full = snapshots.length >= exportLimit;

  return (
    <PageFrame className={styles.content} width="reading">
      <PageHeader back="settings" title={<>Export</>} />
      <section aria-labelledby="export-everything">
        <SectionHeader
          headingId="export-everything"
          title="Export everything"
          variant="section"
        />
        <div className={styles.body}>
          <p>
            One ZIP with complete JSON, readable Entry Markdown, CSV tables, and
            your original photos. It includes Trash and AI conversations.
          </p>
          <p>
            The ZIP is not encrypted, so anyone you share it with can read it.
            Sync every device first; changes still waiting offline are not
            included.
          </p>
          <div className={styles.actions}>
            <Button
              variant="primary"
              type="button"
              disabled={busy || full}
              onClick={exportEverything}
            >
              {progress?.phase === "preparing"
                ? "Preparing export…"
                : "Export everything"}
            </Button>
          </div>
          {full ? (
            <p className={styles.footnote}>
              Discard a recent export below to make a new one.
            </p>
          ) : null}
        </div>
      </section>
      {progress ? (
        <div className={styles.notice} role="status">
          <p>
            {progress.phase === "preparing"
              ? "Preparing a consistent copy of everything…"
              : `Downloading · ${((progress.bytes ?? 0) / 1_048_576).toFixed(1)} MB received`}
          </p>
          {progress.phase === "downloading" ? (
            <div className={styles.actions}>
              <Button
                variant="secondary"
                type="button"
                onClick={() => active.current?.abort()}
              >
                Cancel download
              </Button>
            </div>
          ) : null}
        </div>
      ) : null}
      {message ? (
        <p className={styles.notice} role="status">
          {message}
        </p>
      ) : null}
      {snapshots.length > 0 ? (
        <section aria-labelledby="recent-exports">
          <SectionHeader
            headingId="recent-exports"
            title="Recent exports"
            variant="section"
          />
          <p className={styles.intro}>
            Each export can be downloaded again for 24 hours and keeps the copy
            it made, even if you later edit or delete Entries. Discard one to
            delete its copy sooner.
          </p>
          <ul className={styles.rows}>
            {snapshots.map((snapshot) => (
              <li className={styles.row} key={snapshot.id}>
                <div className={styles.rowCopy}>
                  <h3>{exportTime(snapshot.captured_at, timezone)}</h3>
                  <p>
                    <SeparatedList spacing="word">
                      <span>
                        {countLabel(snapshot.datasets.entries ?? 0, "Entry")}
                      </span>
                      <span>
                        {countLabel(
                          snapshot.datasets.media_objects ?? 0,
                          "media file",
                        )}
                      </span>
                      <span>
                        Available until{" "}
                        {exportTime(snapshot.expires_at, timezone)}
                      </span>
                    </SeparatedList>
                  </p>
                </div>
                <div className={styles.actions}>
                  <Button
                    variant="secondary"
                    type="button"
                    disabled={busy}
                    onClick={() => downloadAgain(snapshot)}
                  >
                    Download again
                  </Button>
                  <Button
                    variant="secondary"
                    type="button"
                    disabled={busy}
                    onClick={() => setDiscard(snapshot)}
                  >
                    Discard
                  </Button>
                </div>
                {discard?.id === snapshot.id ? (
                  <div className={styles.notice}>
                    <p>
                      Discard this export? Your Entries and any ZIP you already
                      downloaded stay unchanged.
                    </p>
                    <div className={styles.actions}>
                      <Button
                        variant="danger"
                        type="button"
                        disabled={busy}
                        onClick={() => discardSnapshot(snapshot)}
                      >
                        Confirm discard
                      </Button>
                      <Button
                        variant="secondary"
                        type="button"
                        disabled={busy}
                        onClick={() => setDiscard(null)}
                      >
                        Keep export
                      </Button>
                    </div>
                  </div>
                ) : null}
              </li>
            ))}
          </ul>
        </section>
      ) : null}
      <p className={styles.footnote}>
        For a large library, use Chrome or Edge to stream directly to a file, or
        the iOS app to download to disk. Other browsers may hold the ZIP in
        memory before saving. If a download exceeds the server time limit, it
        fails explicitly rather than leaving a falsely complete backup.
      </p>
    </PageFrame>
  );
}

function exportTime(value: string, timezone: string) {
  return new Intl.DateTimeFormat("en-US", {
    dateStyle: "medium",
    timeStyle: "short",
    timeZone: timezone,
  }).format(new Date(value));
}

// Asks where to save while the click still counts as the person's action. Throws when they
// cancel; resolves to undefined where the browser cannot save to a chosen file.
async function openSink(
  snapshot: Pick<ExportSnapshot, "captured_at" | "id">,
): Promise<FileSink | undefined> {
  const picker = (window as PickerWindow).showSaveFilePicker;
  if (!picker) return undefined;
  const handle = await picker.call(window, {
    suggestedName: exportFilename(snapshot),
    types: [
      {
        description: "ZIP file",
        accept: { "application/zip": [".zip"] },
      },
    ],
  });
  return handle.createWritable();
}
