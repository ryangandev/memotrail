import { adapterFor, detectSource, type ScanItem } from "./adapters";
import {
  dateWithProperty,
  parseDatePropertyText,
  resolveImportDate,
} from "./dates";
import { importLimits } from "./limits";
import {
  importWarnings,
  type ImportCandidate,
  type ImportFolderSummary,
  type ImportItemMedia,
  type ImportScanTotals,
  type ImportSource,
} from "./types";
import { ImportError, type ZipArchive } from "./zip";

/** What the scan stores for an item: the candidate without its photos, which live in media. */
export type ImportPayload = Omit<ImportCandidate, "photos">;

export type ScanRow = {
  source_key: string;
  folder_path: string[];
  content_hash?: string;
  status?: "pending" | "skipped";
  reason?: string;
  payload?: ImportPayload;
  media?: ImportItemMedia;
};

export type ScanSink = {
  /** Stores a batch and returns how many rows were new. */
  add(rows: ScanRow[]): Promise<number>;
};

export function toScanRow(item: ScanItem): ScanRow {
  if (item.kind === "skipped")
    return {
      folder_path: item.folderPath,
      reason: item.reason,
      source_key: item.sourceKey,
      status: "skipped",
    };
  const { photos, ...payload } = item.candidate;
  return {
    content_hash: item.contentHash,
    folder_path: item.candidate.folderPath,
    media: {
      photos: photos.map((photo) => ({ ...photo, status: "pending" as const })),
    },
    payload,
    source_key: item.candidate.sourceKey,
    status: "pending",
  };
}

/** How many items a Notion property would date, so the best one can be offered first. */
type PropertyStats = {
  dated: number;
  undatedCovered: number;
  from: string | null;
  to: string | null;
};

const preferredDateProperties = [
  "date",
  "created",
  "created time",
  "created at",
  "day",
];

class Totals {
  properties = new Map<string, PropertyStats>();
  entries = 0;
  photos = 0;
  photoBytes = 0;
  undated = 0;
  unparsedDates = 0;
  duplicateKeys = 0;
  from: string | null = null;
  to: string | null = null;
  skippedResources = new Map<string, number>();
  skippedItems = new Map<string, number>();
  warnings = new Map<string, number>();
  folders = new Map<string, ImportFolderSummary>();
  foldersTruncated = false;
  parents = new Set<string>();

  constructor(private timezone: string) {}

  addEntry(candidate: ImportCandidate) {
    this.entries += 1;
    this.photos += candidate.photos.length;
    this.photoBytes += candidate.photos.reduce((sum, p) => sum + p.byteSize, 0);
    const resolved = resolveImportDate(candidate.date, {
      fileModifiedAt: null,
      timezone: this.timezone,
      undated: "leave",
    });
    if (resolved.occurredStart) {
      const day = resolved.occurredStart.slice(0, 10);
      if (!this.from || day < this.from) this.from = day;
      if (!this.to || day > this.to) this.to = day;
    } else {
      this.undated += 1;
      this.addProperties(candidate, true);
    }
    if (resolved.occurredStart) this.addProperties(candidate, false);
    if (candidate.warnings.includes(importWarnings.dateUnparsed))
      this.unparsedDates += 1;
    for (const warning of candidate.warnings)
      this.warnings.set(warning, (this.warnings.get(warning) ?? 0) + 1);
    for (const skipped of candidate.skippedResources)
      this.skippedResources.set(
        skipped.kind,
        (this.skippedResources.get(skipped.kind) ?? 0) + skipped.count,
      );
    const parent = candidate.folderPath.at(-1);
    if (parent) this.parents.add(parent);
    // Every folder along the path counts the item, so a tree can show totals at each level.
    for (let depth = 1; depth <= candidate.folderPath.length; depth += 1) {
      const path = candidate.folderPath.slice(0, depth);
      const key = JSON.stringify(path);
      const existing = this.folders.get(key);
      if (existing) {
        existing.entries += 1;
        existing.photos += candidate.photos.length;
      } else if (this.folders.size < importLimits.maxPreviewFolders) {
        this.folders.set(key, {
          entries: 1,
          path,
          photos: candidate.photos.length,
        });
      } else this.foldersTruncated = true;
    }
  }

  private addProperties(candidate: ImportCandidate, undated: boolean) {
    for (const [name, text] of Object.entries(candidate.dateProperties ?? {})) {
      const resolved = resolveImportDate(
        dateWithProperty({ precision: "unknown" }, { [name]: text }, name),
        { fileModifiedAt: null, timezone: this.timezone, undated: "leave" },
      );
      if (!resolved.occurredStart || !parseDatePropertyText(text)) continue;
      const stats = this.properties.get(name) ?? {
        dated: 0,
        from: null,
        to: null,
        undatedCovered: 0,
      };
      const day = resolved.occurredStart.slice(0, 10);
      if (undated) {
        stats.dated += 1;
        stats.undatedCovered += 1;
      }
      if (!stats.from || day < stats.from) stats.from = day;
      if (!stats.to || day > stats.to) stats.to = day;
      this.properties.set(name, stats);
    }
  }

  /** The date property that dates the most items, with a plain name as the tie breaker. */
  private bestProperty(): string | null {
    let best: string | null = null;
    let bestScore = 0;
    for (const [name, stats] of this.properties) {
      const score =
        stats.dated * 2 +
        (preferredDateProperties.includes(name.trim().toLowerCase()) ? 1 : 0);
      if (stats.dated > 0 && score > bestScore) {
        best = name;
        bestScore = score;
      }
    }
    return best;
  }

  addSkipped(reason: string) {
    this.skippedItems.set(reason, (this.skippedItems.get(reason) ?? 0) + 1);
  }

  toJson(detected: ImportScanTotals["detected"]): ImportScanTotals {
    const record = (map: Map<string, number>) => Object.fromEntries(map);
    const property = this.bestProperty();
    const stats = property ? this.properties.get(property) : undefined;
    const from =
      stats?.from && (!this.from || stats.from < this.from)
        ? stats.from
        : this.from;
    const to =
      stats?.to && (!this.to || stats.to > this.to) ? stats.to : this.to;
    return {
      dateRange: from && to ? { from, to } : null,
      detected,
      distinctParentFolders: this.parents.size,
      duplicateKeys: this.duplicateKeys,
      entries: this.entries,
      folders: [...this.folders.values()].sort((a, b) =>
        a.path.join("/").localeCompare(b.path.join("/")),
      ),
      foldersTruncated: this.foldersTruncated,
      notionDateProperties: [...this.properties.keys()],
      notionDateProperty: property,
      photoBytes: this.photoBytes,
      photos: this.photos,
      skippedItems: record(this.skippedItems),
      skippedResources: [...this.skippedResources].map(([kind, count]) => ({
        count,
        kind,
      })),
      undated: Math.max(0, this.undated - (stats?.undatedCovered ?? 0)),
      unparsedDates: this.unparsedDates,
      warnings: record(this.warnings),
    };
  }
}

/**
 * Reads the whole archive with the job's adapter and stores what it finds. Nothing reaches
 * the library; the preview decides. Item batches go out as they fill, so memory stays flat.
 */
export async function scanArchive(
  archive: ZipArchive,
  options: { source: ImportSource; timezone: string },
  sink: ScanSink,
): Promise<ImportScanTotals> {
  const adapter = adapterFor(options.source);
  const totals = new Totals(options.timezone);
  const detected = detectSource(archive);
  let batch: ScanRow[] = [];
  const flush = async () => {
    if (batch.length === 0) return;
    const added = await sink.add(batch);
    totals.duplicateKeys += batch.length - added;
    batch = [];
  };
  let candidates = 0;
  for await (const item of adapter.scan(archive, { source: options.source })) {
    if (item.kind === "entry") {
      candidates += 1;
      if (candidates > importLimits.maxEntriesPerJob)
        throw new ImportError("too_many_entries");
      totals.addEntry(item.candidate);
      if (totals.photos > importLimits.maxPhotosPerJob)
        throw new ImportError("too_many_photos");
    } else totals.addSkipped(item.reason);
    batch.push(toScanRow(item));
    if (batch.length >= importLimits.scanBatch) await flush();
  }
  await flush();
  if (totals.entries === 0) throw new ImportError("empty_import");
  const result = totals.toJson(detected);
  return result;
}
