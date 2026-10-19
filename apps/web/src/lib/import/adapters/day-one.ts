import { convertMarkdownNote } from "../convert-note";
import { importLimits } from "../limits";
import { importWarnings, type ImportDate } from "../types";
import { ImportError, type ZipArchive, type ZipMember } from "../zip";
import {
  MemberIndex,
  baseName,
  finalizeDraft,
  resolveResources,
  stem,
  type ImportAdapter,
  type ScanItem,
} from "./shared";

type DayOnePhoto = {
  identifier?: string;
  md5?: string;
  type?: string;
  orderInEntry?: number;
};

type DayOneEntry = {
  uuid?: string;
  creationDate?: string;
  modifiedDate?: string;
  timeZone?: string;
  text?: string;
  tags?: unknown;
  location?: Record<string, unknown>;
  photos?: DayOnePhoto[];
  videos?: unknown[];
  audios?: unknown[];
  pdfAttachments?: unknown[];
};

const momentReference = /dayone-moment:\/\/([0-9A-Za-z-]+)/g;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** The JSON files that could be journals: at the top, or one folder down. */
function journalFiles(archive: ZipArchive): ZipMember[] {
  return archive.members.filter(
    (member) =>
      !member.container &&
      /\.json$/i.test(member.path) &&
      member.path.split("/").length <= 2 &&
      !baseName(member.path).startsWith("."),
  );
}

function strings(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string")
    : [];
}

function locationLabel(location: DayOneEntry["location"]): string | null {
  if (!isRecord(location)) return null;
  const parts: string[] = [];
  for (const key of [
    "placeName",
    "localityName",
    "administrativeArea",
    "country",
  ]) {
    const value = location[key];
    if (
      typeof value === "string" &&
      value.trim() &&
      !parts.includes(value.trim())
    )
      parts.push(value.trim());
  }
  return parts.length > 0 ? parts.join(", ").slice(0, 500) : null;
}

function instantOf(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const ms = Date.parse(value);
  return Number.isFinite(ms) ? new Date(ms).toISOString() : null;
}

/**
 * A Day One JSON export: a ZIP with Journal.json (or one JSON per journal) and a photos folder
 * whose files are named by checksum. Every entry has an exact time and a time zone, which map
 * straight onto the Entry's.
 */
export const dayOneAdapter: ImportAdapter = {
  detect(archive) {
    const json = journalFiles(archive);
    if (json.length === 0) return 0;
    const hasPhotos = archive.members.some((member) =>
      /(^|\/)photos\//i.test(member.path),
    );
    const named = json.some((member) =>
      /^journal(-\d+)?\.json$/i.test(baseName(member.path)),
    );
    if (named && hasPhotos) return 0.9;
    if (named) return 0.8;
    return hasPhotos ? 0.5 : 0.3;
  },

  async *scan(archive) {
    const files = journalFiles(archive).sort((a, b) =>
      a.path.localeCompare(b.path),
    );
    const index = new MemberIndex(archive.members);
    const several = files.length > 1;
    for (const file of files) {
      let parsed: unknown;
      try {
        parsed = JSON.parse(
          await archive.readText(file, importLimits.maxJournalJsonBytes),
        );
      } catch (error) {
        if (error instanceof ImportError && error.code === "file_too_large")
          throw error;
        // A JSON file that is not a journal is not an error.
        continue;
      }
      if (!isRecord(parsed) || !Array.isArray(parsed.entries)) continue;
      const folderPath = several ? [stem(file.path)] : [];
      for (const raw of parsed.entries) {
        if (!isRecord(raw)) continue;
        yield* scanEntry(raw as DayOneEntry, file, index, folderPath);
      }
    }
  },
};

function* scanEntry(
  entry: DayOneEntry,
  file: ZipMember,
  index: MemberIndex,
  folderPath: string[],
): Generator<ScanItem> {
  const uuid = typeof entry.uuid === "string" ? entry.uuid.trim() : "";
  if (!uuid) {
    yield {
      folderPath,
      kind: "skipped",
      reason: "no_id",
      sourceKey: `${file.path}#?`,
    };
    return;
  }
  const text = typeof entry.text === "string" ? entry.text : "";
  const converted = convertMarkdownNote(text, null, { collectHashtags: false });

  const created = instantOf(entry.creationDate);
  const date: ImportDate = created
    ? {
        instant: created,
        precision: "exact",
        ...(typeof entry.timeZone === "string"
          ? { timezone: entry.timeZone }
          : {}),
      }
    : { precision: "unknown" };

  // Photos, in the order the writing shows them, then any the writing does not mention.
  const photos = Array.isArray(entry.photos)
    ? entry.photos.filter((photo): photo is DayOnePhoto => isRecord(photo))
    : [];
  const appearance = [...text.matchAll(momentReference)].map(
    (match) => match[1],
  );
  const rank = (photo: DayOnePhoto) => {
    const at = photo.identifier ? appearance.indexOf(photo.identifier) : -1;
    return at >= 0 ? at : appearance.length + (photo.orderInEntry ?? 0);
  };
  const ordered = [...photos].sort((a, b) => rank(a) - rank(b));
  const images = ordered.map((photo) => {
    const extension = (photo.type ?? "").toLowerCase().replace(/^\./, "");
    const names = photo.md5
      ? [
          `${photo.md5}.${extension}`,
          `${photo.md5}.${extension === "jpeg" ? "jpg" : extension}`,
        ]
      : [];
    const found = names
      .flatMap((name) => [
        index.resolve(file, `photos/${name}`),
        index.resolve(file, name),
      ])
      .find(Boolean);
    return {
      alt: "",
      src: found ? `/${found.path}` : `missing://${photo.identifier ?? ""}`,
    };
  });

  const extraSkipped = new Map<string, number>();
  const bump = (kind: string, count: number) => {
    if (count > 0)
      extraSkipped.set(kind, (extraSkipped.get(kind) ?? 0) + count);
  };
  bump("video", Array.isArray(entry.videos) ? entry.videos.length : 0);
  bump("audio", Array.isArray(entry.audios) ? entry.audios.length : 0);
  bump(
    "pdf",
    Array.isArray(entry.pdfAttachments) ? entry.pdfAttachments.length : 0,
  );
  const resources = resolveResources(index, file, images, extraSkipped);

  yield* finalizeDraft({
    blocks: converted.blocks,
    date,
    folderPath,
    locationLabel: locationLabel(entry.location),
    photos: resources.photos,
    skipped: resources.skipped,
    source: "day_one",
    sourceCreatedAt: created,
    sourceKey: uuid,
    sourceModifiedAt: instantOf(entry.modifiedDate),
    tagNames: strings(entry.tags),
    title: converted.titleSource === "fallback" ? null : converted.title,
    warnings: [
      ...resources.warnings,
      ...(created ? [] : [importWarnings.dateUnparsed]),
    ],
  });
}
