import type { ImportSource } from "../types";
import type { ZipArchive } from "../zip";
import { markdownAdapter } from "./markdown";
import type { ImportAdapter } from "./shared";

export type { ImportAdapter, ScanItem } from "./shared";

/** The adapters in the order they are tried when detecting a format. */
const adapters: { source: ImportSource; adapter: ImportAdapter }[] = [
  { adapter: markdownAdapter, source: "markdown" },
];

/** Apple Notes' Markdown export is read by the Markdown adapter. */
export function adapterFor(source: ImportSource): ImportAdapter {
  const found = adapters.find((item) => item.source === source);
  return (
    found?.adapter ??
    (source === "apple_notes" ? markdownAdapter : markdownAdapter)
  );
}

/** What an archive looks like, so a card that does not match can be questioned. */
export function detectSource(
  archive: ZipArchive,
): { source: ImportSource; confidence: number } | null {
  let best: { source: ImportSource; confidence: number } | null = null;
  for (const { source, adapter } of adapters) {
    const confidence = adapter.detect(archive);
    if (confidence > (best?.confidence ?? 0)) best = { confidence, source };
  }
  return best;
}
