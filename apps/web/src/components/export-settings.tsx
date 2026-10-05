"use client";
import { notify } from "@/components/app-toast";
import { PageHeader } from "@/components/page-header";
import { Button } from "@/components/button";
import { useEffect, useRef, useState } from "react";
import { PageFrame } from "@/components/page-frame";
import { SeparatedList } from "@/components/separated-list";
import {
  appendExportTail,
  exportFilename,
  hasCompleteExport,
  type ExportAction,
  type ExportSnapshot,
} from "@/lib/export/contracts";
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
export function ExportSettings({
  initial,
  initialError,
}: {
  initial: ExportSnapshot[];
  initialError: boolean;
}) {
  const [snapshots, setSnapshots] = useState<ExportSnapshot[]>(initial);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState(
    initialError ? "Could not load snapshots. Refresh to retry." : "",
  );
  const [bytes, setBytes] = useState<number | null>(null);
  const [discard, setDiscard] = useState<ExportSnapshot | null>(null);
  const pendingCreate = useRef<string | null>(null);
  const active = useRef<AbortController | null>(null);
  async function refresh(signal?: AbortSignal) {
    const response = await exportRequest({ action: "list" }, signal);
    const result = await response.json();
    setSnapshots(result.snapshots);
  }
  useEffect(() => {
    return () => {
      active.current?.abort();
    };
  }, []);
  async function change(action: "create" | "discard" | "list", id?: string) {
    if (active.current) return;
    const controller = new AbortController();
    active.current = controller;
    setBusy(true);
    setMessage("");
    try {
      if (action === "create") {
        pendingCreate.current ??= crypto.randomUUID();
        await exportRequest(
          { action, id: pendingCreate.current },
          controller.signal,
        );
        pendingCreate.current = null;
        notify.success(
          "Snapshot prepared. Download it on either device within 24 hours.",
        );
      } else if (action === "discard") {
        await exportRequest({ action, id }, controller.signal);
        setDiscard(null);
        notify.success(
          "Temporary copy discarded. Your records and downloaded files are unchanged.",
        );
      }
      await refresh(controller.signal);
    } catch (error) {
      if (
        error instanceof ExportRequestError &&
        ["expired", "request_unavailable"].includes(error.code)
      )
        pendingCreate.current = null;
      if (!controller.signal.aborted)
        setMessage(
          error instanceof Error
            ? error.message
            : "Could not update snapshots. Retry uses the same request.",
        );
    } finally {
      active.current = null;
      setBusy(false);
    }
  }
  async function download(snapshot: ExportSnapshot) {
    if (active.current) return;
    const controller = new AbortController();
    active.current = controller;
    setBusy(true);
    setBytes(0);
    setMessage("");
    let sink: FileSink | undefined;
    try {
      const picker = (window as PickerWindow).showSaveFilePicker;
      // Invoke the picker before any network await, while the click is active.
      if (picker) {
        const handle = await picker.call(window, {
          suggestedName: exportFilename(snapshot),
          types: [
            {
              description: "ZIP archive",
              accept: { "application/zip": [".zip"] },
            },
          ],
        });
        sink = await handle.createWritable();
      }
      const response = await exportRequest(
        { action: "download", id: snapshot.id },
        controller.signal,
      );
      if (
        !response.body ||
        !response.headers.get("content-type")?.includes("application/zip")
      )
        throw new Error("Invalid archive response.");
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
          setBytes(received);
        }
      } finally {
        reader.releaseLock();
      }
      if (!hasCompleteExport(tail)) throw new Error("Incomplete ZIP.");
      controller.signal.throwIfAborted();
      if (sink) {
        await sink.close();
        sink = undefined;
        notify.success(
          "Complete ZIP saved. Keep this private copy somewhere safe.",
        );
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
          "Complete ZIP prepared. Check your browser downloads to finish saving it.",
        );
      }
    } catch (error) {
      controller.abort();
      await sink?.abort().catch(() => {});
      setMessage(
        error instanceof DOMException && error.name === "AbortError"
          ? "Download cancelled. The snapshot is still available."
          : "Download did not complete. An original may be missing or changed, or the connection was interrupted. Retry this snapshot or prepare a new one. No complete ZIP was saved.",
      );
    } finally {
      active.current = null;
      setBusy(false);
      setBytes(null);
    }
  }
  return (
    <PageFrame className={styles.content} variant="compact">
      <PageHeader
        title={<>Export archive</>}
        eyebrow={<>YOUR ARCHIVE, TO KEEP</>}
        description={<>A portable copy of your story. No AI processing.</>}
      />
      <section className={styles.card}>
        <h2>Everything, in one ZIP</h2>
        <p>
          Complete JSON, readable Entry Markdown, structured CSV tables, and
          original photos. Includes Trash, relationships, and AI conversations.
        </p>
        <p>
          The ZIP is not encrypted. Anyone you share it with can read it.
          Unsynced offline changes are not included; sync every device first.
        </p>
      </section>
      <section className={styles.card}>
        <h2>Prepare a snapshot</h2>
        <p>
          Capture one consistent moment across your devices. Temporary copies
          retain that content for 24 hours, even if you later edit or delete the
          originals. Discard a snapshot to remove its copied content sooner.
        </p>
        <p>
          Keep up to two snapshots. Original media is verified during download;
          changed or missing files stop the export.
        </p>
        <div className={styles.actions}>
          <Button
            variant="primary"
            type="submit"
            disabled={busy || snapshots.length >= 2}
            onClick={() => void change("create")}
          >
            Prepare snapshot
          </Button>
          <Button
            variant="secondary"
            type="submit"
            disabled={busy}
            onClick={() => void change("list")}
          >
            Refresh
          </Button>
        </div>
      </section>
      {message && (
        <p className={styles.notice} role="status">
          {message}
        </p>
      )}
      {bytes !== null && (
        <div className={styles.notice} role="status">
          <p>Downloading · {(bytes / 1_048_576).toFixed(1)} MB received</p>
          <Button
            variant="secondary"
            type="submit"
            onClick={() => active.current?.abort()}
          >
            Cancel download
          </Button>
        </div>
      )}
      <section aria-label="Available snapshots" className={styles.snapshots}>
        <h2>Available snapshots</h2>
        {snapshots.length === 0 ? (
          <p>No snapshots yet. Your archive is unchanged.</p>
        ) : (
          snapshots.map((snapshot) => (
            <article className={styles.card} key={snapshot.id}>
              <h3>{new Date(snapshot.captured_at).toLocaleString()}</h3>
              <p>
                <SeparatedList spacing="word">
                  <span>{snapshot.row_count.toLocaleString()} records</span>
                  <span>{snapshot.datasets.entries ?? 0} Entries</span>
                  <span>
                    {snapshot.datasets.media_objects ?? 0} media files
                  </span>
                </SeparatedList>
              </p>
              <p>Expires {new Date(snapshot.expires_at).toLocaleString()}</p>
              <div className={styles.actions}>
                <Button
                  variant="secondary"
                  type="submit"
                  disabled={busy}
                  onClick={() => void download(snapshot)}
                >
                  Download ZIP
                </Button>
                <Button
                  variant="danger"
                  type="submit"
                  disabled={busy}
                  onClick={() => setDiscard(snapshot)}
                >
                  Discard snapshot
                </Button>
              </div>
              {discard?.id === snapshot.id && (
                <div className={styles.notice}>
                  <p>
                    Discard this temporary copy? Your original records and
                    downloaded ZIPs will stay unchanged.
                  </p>
                  <div className={styles.actions}>
                    <Button
                      variant="danger"
                      type="submit"
                      disabled={busy}
                      onClick={() => void change("discard", snapshot.id)}
                    >
                      Confirm discard
                    </Button>
                    <Button
                      variant="secondary"
                      type="submit"
                      disabled={busy}
                      onClick={() => setDiscard(null)}
                    >
                      Keep snapshot
                    </Button>
                  </div>
                </div>
              )}
            </article>
          ))
        )}
      </section>
      <p className={styles.footnote}>
        For large archives, use Chrome or Edge to stream directly to a file, or
        the iOS app to download to disk. Other browsers may hold the ZIP in
        memory before saving. If a download exceeds the server time limit, it
        fails explicitly rather than leaving a falsely complete backup.
      </p>
    </PageFrame>
  );
}
