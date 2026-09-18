import { createHash } from "node:crypto";
import { Readable, type PassThrough } from "node:stream";
import type { SupabaseClient } from "@supabase/supabase-js";
import { ZipFile } from "yazl";
import {
  EXPORT_COMPLETE,
  csvCell,
  entryMarkdown,
  isUUID,
  mediaArchivePath,
  type ExportSnapshot,
} from "./contracts";

export class ExportError extends Error {
  constructor(
    public code: string,
    public status: number,
    message: string,
  ) {
    super(message);
  }
}
export function exportDatabaseError(message?: string): never {
  if (message === "export_request_unavailable")
    throw new ExportError(
      "request_unavailable",
      409,
      "This request ID is unavailable. Prepare a new snapshot.",
    );
  if (message === "export_expired")
    throw new ExportError(
      "expired",
      410,
      "This snapshot expired or was discarded. Prepare a new snapshot.",
    );
  if (message?.includes("limit"))
    throw new ExportError(
      "limit",
      429,
      "Keep at most two snapshots. Discard an old snapshot or wait before preparing another.",
    );
  throw new ExportError(
    "unavailable",
    503,
    "Could not read the export snapshot. Retry without changing your records.",
  );
}
type Row = Record<string, unknown>;
type Page = {
  snapshot: ExportSnapshot;
  rows: { position: number; dataset: string; value: Row }[];
  has_more: boolean;
  next_cursor: number;
};
async function readPage(
  client: SupabaseClient,
  id: string,
  after: number,
  signal: AbortSignal,
) {
  const { data, error } = await client
    .rpc("read_export_snapshot", {
      p_snapshot_id: id,
      p_after: after,
      p_limit: 100,
    })
    .abortSignal(signal);
  if (error) exportDatabaseError(error.message);
  if (!data)
    throw new ExportError(
      "not_found",
      404,
      "This snapshot is not available to this account.",
    );
  return data as Page;
}
export async function getExportSnapshot(
  client: SupabaseClient,
  id: string,
  signal: AbortSignal,
) {
  const { snapshot } = await readPage(client, id, 0, signal);
  if (
    snapshot.id !== id ||
    snapshot.schema_version !== 1 ||
    !Number.isSafeInteger(snapshot.row_count) ||
    Object.entries(snapshot.datasets).some(
      ([name, count]) =>
        !/^[a-z_]+$/.test(name) || !Number.isSafeInteger(count) || count < 0,
    ) ||
    Object.values(snapshot.datasets).reduce((a, b) => a + b, 0) !==
      snapshot.row_count
  )
    throw new ExportError(
      "invalid_snapshot",
      503,
      "The export snapshot needs a compatible server version.",
    );
  return snapshot;
}
async function* datasetRows(
  client: SupabaseClient,
  snapshot: ExportSnapshot,
  name: string,
  signal: AbortSignal,
) {
  const names = Object.keys(snapshot.datasets).sort();
  const start = names
    .slice(0, names.indexOf(name))
    .reduce((sum, key) => sum + snapshot.datasets[key], 0);
  const end = start + snapshot.datasets[name];
  let cursor = start;
  while (cursor < end) {
    signal.throwIfAborted();
    const page = await readPage(client, snapshot.id, cursor, signal);
    if (
      page.snapshot.captured_at !== snapshot.captured_at ||
      page.rows.length === 0
    )
      throw new Error("Export snapshot changed.");
    for (const row of page.rows) {
      if (cursor === end) break;
      if (row.position !== cursor + 1 || row.dataset !== name)
        throw new Error("Export page is incomplete.");
      cursor = row.position;
      yield row.value;
    }
  }
}
async function* jsonRows(rows: AsyncIterable<Row>) {
  yield "[\n";
  let separator = "";
  for await (const row of rows) {
    yield separator + JSON.stringify(row);
    separator = ",\n";
  }
  yield "\n]\n";
}
async function* csvRows(rows: AsyncIterable<Row>) {
  yield "\uFEFF";
  let fields: string[] | undefined;
  for await (const row of rows) {
    if (!fields) {
      fields = Object.keys(row).sort();
      yield fields.map(csvCell).join(",") + "\r\n";
    }
    yield fields.map((key) => csvCell(row[key])).join(",") + "\r\n";
  }
  if (!fields) yield '"id"\r\n';
}
const readme = `# MemoTrail complete export

This is a private, unencrypted copy of your archive. Keep it somewhere safe.
It includes Trash, histories, relationships, AI conversations and usage, and original attachments.

manifest.json identifies the immutable snapshot and every canonical dataset.
data/*.json contains complete canonical rows with stable IDs and relationships, including empty datasets.
entries/*.md contains original Entry writing with metadata; filenames use stable IDs, not titles.
tables/*.csv contains readable structured views. Empty tables contain an id header only.
CSV string cells that could run spreadsheet formulas are prefixed with an apostrophe. JSON remains unchanged.
media/* contains all registered attachment variants, including originals, named by attachment ID and variant.
checksums.json maps each media file to its storage identity, byte count, and SHA-256 digest.

Original writing may contain links, HTML, or other untrusted content. Use a viewer you trust.
Dates and partial date precision are preserved without inventing missing dates.
JSON is the authoritative interchange format; an automatic import UI is not implemented yet.

The server snapshot expires after 24 hours and can be discarded sooner without changing your records.
Media is checked against its captured ETag and size while downloading. Missing or changed files fail the export.
A download is complete only when the ZIP closes successfully with its MemoTrail completion comment.
Unzip with a tool that validates ZIP checksums; checksums.json additionally verifies original media bytes.
`;

// Only one source is read at a time. Backpressure reaches Storage and paginated RPCs.
// ZIP directory and checksum metadata grow with file count, not attachment byte size.
export function createExportArchive(
  client: SupabaseClient,
  ownerID: string,
  snapshot: ExportSnapshot,
  requestSignal: AbortSignal,
) {
  const controller = new AbortController();
  const signal = AbortSignal.any([
    requestSignal,
    controller.signal,
    AbortSignal.timeout(280_000),
  ]);
  const zip = new ZipFile();
  const output = zip.outputStream as PassThrough;
  let current: Readable | undefined;
  const fail = () => {
    const error = new Error(
      "Export interrupted. No complete archive was produced.",
    );
    current?.destroy(error);
    output.destroy(error);
  };
  signal.addEventListener("abort", fail, { once: true });
  if (signal.aborted) queueMicrotask(fail);
  zip.on("error", () => controller.abort());
  output.on("error", () => controller.abort());
  output.once("close", () => {
    signal.removeEventListener("abort", fail);
    controller.abort();
  });
  const add = (
    path: string,
    source: AsyncIterable<string | Uint8Array>,
    compress = true,
  ) =>
    new Promise<void>((resolve, reject) => {
      const abort = () => reject(new Error("Export interrupted."));
      signal.addEventListener("abort", abort, { once: true });
      if (signal.aborted) {
        signal.removeEventListener("abort", abort);
        reject(new Error("Export interrupted."));
        return;
      }
      zip.addReadStreamLazy(
        path,
        { compress, mtime: new Date(snapshot.captured_at), mode: 0o100600 },
        (callback) => {
          if (signal.aborted) {
            callback(new Error("Export interrupted."), Readable.from([]));
            return;
          }
          const stream = Readable.from(source);
          current = stream;
          stream.once("end", resolve);
          stream.once("error", reject);
          stream.once("close", () =>
            signal.removeEventListener("abort", abort),
          );
          callback(null, stream);
        },
      );
    });
  const text = async function* (value: string) {
    yield value;
  };
  const produce = async () => {
    const names = Object.keys(snapshot.datasets).sort();
    await add("README.md", text(readme));
    await add(
      "manifest.json",
      text(
        JSON.stringify(
          {
            format: "memotrail",
            version: 1,
            snapshot,
            datasets: Object.fromEntries(
              names.map((name) => [
                name,
                { path: `data/${name}.json`, count: snapshot.datasets[name] },
              ]),
            ),
          },
          null,
          2,
        ),
      ),
    );
    for (const name of names) {
      await add(
        `data/${name}.json`,
        jsonRows(datasetRows(client, snapshot, name, signal)),
      );
      if (
        [
          "homes",
          "vehicles",
          "goals",
          "locations",
          "places",
          "people",
          "timeline_items",
        ].includes(name)
      )
        await add(
          `tables/${name}.csv`,
          csvRows(datasetRows(client, snapshot, name, signal)),
        );
    }
    for await (const entry of datasetRows(
      client,
      snapshot,
      "entries",
      signal,
    )) {
      if (!isUUID(entry.id)) throw new Error("Invalid Entry identity.");
      await add(`entries/${entry.id}.md`, text(entryMarkdown(entry)));
    }
    const checksums: Row[] = [];
    for await (const media of datasetRows(
      client,
      snapshot,
      "media_objects",
      signal,
    )) {
      if (
        !media.available ||
        media.bucket_id !== "entry-media" ||
        typeof media.object_path !== "string" ||
        media.object_path.split("/")[0] !== ownerID ||
        typeof media.etag !== "string" ||
        !media.etag ||
        media.byte_size == null ||
        !Number.isSafeInteger(Number(media.byte_size)) ||
        Number(media.byte_size) < 0
      )
        throw new Error("Original media is missing or cannot be verified.");
      const path = mediaArchivePath(media);
      const { data, error } = await client.storage
        .from("entry-media")
        .createSignedUrl(media.object_path, 60);
      if (error || !data) throw new Error("Original media is unavailable.");
      const response = await fetch(data.signedUrl, {
        signal,
        cache: "no-store",
      });
      const etag = response.headers.get("etag")?.replace(/^"|"$/g, "");
      if (
        !response.ok ||
        !response.body ||
        etag !== media.etag.replace(/^"|"$/g, "")
      ) {
        await response.body?.cancel();
        throw new Error("Original media changed after capture.");
      }
      const hash = createHash("sha256");
      let bytes = 0;
      const mediaBody = response.body;
      const chunks = async function* () {
        const reader = mediaBody.getReader();
        try {
          while (true) {
            const next = await reader.read();
            if (next.done) break;
            signal.throwIfAborted();
            bytes += next.value.length;
            hash.update(next.value);
            yield next.value;
          }
        } finally {
          await reader.cancel().catch(() => {});
          reader.releaseLock();
        }
        if (bytes !== Number(media.byte_size))
          throw new Error("Original media size changed after capture.");
      };
      await add(path, chunks(), false);
      checksums.push({
        ...media,
        archive_path: path,
        bytes,
        sha256: hash.digest("hex"),
      });
    }
    // A last owner-scoped read catches expiry/discard during serialization.
    await readPage(client, snapshot.id, snapshot.row_count, signal);
    await add(
      "checksums.json",
      text(JSON.stringify({ complete: true, media: checksums }, null, 2)),
    );
    zip.end({ forceZip64Format: false, comment: EXPORT_COMPLETE });
  };
  void produce().catch(() => controller.abort());
  return Readable.toWeb(output) as ReadableStream<Uint8Array>;
}
