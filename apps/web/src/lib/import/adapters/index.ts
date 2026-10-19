import type { ImportSource } from "../types";
import { ImportError, type ZipArchive } from "../zip";
import { appleJournalAdapter } from "./apple-journal";
import { dayOneAdapter } from "./day-one";
import { markdownAdapter } from "./markdown";
import { notionAdapter } from "./notion";
import type { ImportAdapter } from "./shared";

export type { ImportAdapter, ScanItem } from "./shared";

/** The adapters in the order they are tried when detecting a format. */
const adapters: { source: ImportSource; adapter: ImportAdapter }[] = [
  { adapter: markdownAdapter, source: "markdown" },
  { adapter: appleJournalAdapter, source: "apple_journal" },
  { adapter: notionAdapter, source: "notion" },
  { adapter: dayOneAdapter, source: "day_one" },
];

/** The sources a person can import from: every adapter, and Apple Notes through Markdown. */
export function availableSources(): ImportSource[] {
  return [...adapters.map((item) => item.source), "apple_notes"];
}

/** Apple Notes' Markdown export is read by the Markdown adapter. */
export function adapterFor(source: ImportSource): ImportAdapter {
  const wanted = source === "apple_notes" ? "markdown" : source;
  const found = adapters.find((item) => item.source === wanted);
  if (!found) throw new ImportError("unsupported_source");
  return found.adapter;
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
