import type { RichTextNode } from "@/lib/data/rich-text";
import { dateFromTitle } from "../dates";
import { candidateContentHash } from "../identity";
import { importLimits } from "../limits";
import {
  bodyParts,
  paragraph,
  textNodes,
} from "../rich";
import {
  importWarnings,
  type ImportCandidate,
  type ImportDate,
  type ImportResource,
  type ImportSource,
  type SkippedResource,
} from "../types";
import type { ZipArchive, ZipMember } from "../zip";

/** One thing a scan found: an Entry to import, or an item it had to leave out. */
export type ScanItem =
  | { kind: "entry"; candidate: ImportCandidate; contentHash: string }
  | {
      kind: "skipped";
      sourceKey: string;
      folderPath: string[];
      reason: string;
    };

export type ScanOptions = { source: ImportSource };

/** An export format. Adapters read the archive and produce candidates; the engine does the rest. */
export interface ImportAdapter {
  /** 0 to 1: how much the archive looks like this format. */
  detect(archive: ZipArchive): number;
  scan(archive: ZipArchive, options: ScanOptions): AsyncGenerator<ScanItem>;
}

export type EntryDraft = {
  source: ImportSource;
  sourceKey: string;
  folderPath: string[];
  title: string | null;
  blocks: RichTextNode[];
  /** The date the source states. Unknown when it states none. */
  date: ImportDate;
  /** A date in the file name, used when the source states none and the title has none. */
  fileNameDate?: ImportDate | null;
  tagNames: string[];
  propertyTagNames?: string[];
  locationLabel?: string | null;
  photos?: ImportResource[];
  skipped?: SkippedResource[];
  sourceCreatedAt?: string | null;
  sourceModifiedAt?: string | null;
  fileModifiedAt?: string | null;
  warnings?: string[];
  /** Plain lines added after the writing, such as "State of Mind: Slightly Pleasant". */
  trailingLines?: string[];
};

function shorten(title: string): { title: string; cut: boolean } {
  if (title.length <= importLimits.titleChars) return { cut: false, title };
  const limit = importLimits.titleChars - 3;
  const space = title.lastIndexOf(" ", limit);
  const end = space > limit / 2 ? space : limit;
  return { cut: true, title: `${title.slice(0, end).trimEnd()}...` };
}

/**
 * Applies the shared rules to what an adapter read: a title that is only a date becomes the
 * date, long titles and bodies are cut within the Entry limits, and an item with nothing in
 * it is skipped. The first part of a long body keeps the photos.
 */
export function finalizeDraft(draft: EntryDraft): ScanItem[] {
  const warnings = [...(draft.warnings ?? [])];
  let title = draft.title?.replace(/\s+/g, " ").trim() || null;
  let date = draft.date;

  const titleDate = title ? dateFromTitle(title) : null;
  if (titleDate) {
    if (date.precision === "unknown") date = titleDate;
    title = null;
  }
  if (date.precision === "unknown" && draft.fileNameDate)
    date = draft.fileNameDate;

  const blocks = [...draft.blocks];
  if (title) {
    const shortened = shorten(title);
    if (shortened.cut) {
      blocks.unshift(paragraph(textNodes(title)));
      title = shortened.title;
      warnings.push(importWarnings.titleShortened);
    }
  }
  for (const line of draft.trailingLines ?? [])
    blocks.push(paragraph(textNodes(line)));

  const parts = bodyParts(blocks);
  if (parts.length > 1) warnings.push(importWarnings.bodySplit);
  const photos = draft.photos ?? [];

  const items: ScanItem[] = [];
  parts.forEach((part, index) => {
    const sourceKey =
      index === 0 ? draft.sourceKey : `${draft.sourceKey}#${index + 1}`;
    const partTitle =
      title && parts.length > 1
        ? shorten(`${title} (${index + 1}/${parts.length})`).title
        : title;
    const partPhotos = index === 0 ? photos : [];
    if (!partTitle && !part.body && partPhotos.length === 0) {
      if (index === 0)
        items.push({
          folderPath: draft.folderPath,
          kind: "skipped",
          reason: "empty",
          sourceKey,
        });
      return;
    }
    const candidate: ImportCandidate = {
      bodyRich: part.document,
      date,
      fileModifiedAt: draft.fileModifiedAt ?? null,
      folderPath: draft.folderPath,
      locationLabel: draft.locationLabel ?? null,
      photos: partPhotos,
      propertyTagNames: draft.propertyTagNames ?? [],
      skippedResources: index === 0 ? (draft.skipped ?? []) : [],
      source: draft.source,
      sourceCreatedAt: draft.sourceCreatedAt ?? null,
      sourceKey,
      sourceModifiedAt: draft.sourceModifiedAt ?? null,
      tagNames: draft.tagNames,
      title: partTitle,
      warnings,
    };
    items.push({
      candidate,
      contentHash: candidateContentHash({
        date,
        locationLabel: candidate.locationLabel,
        photoNames: partPhotos.map((photo) => photo.key),
        plainText: part.body,
        propertyTagNames: candidate.propertyTagNames,
        tagNames: candidate.tagNames,
        title: partTitle,
      }),
      kind: "entry",
    });
  });
  return items;
}

// Resources ---------------------------------------------------------------------------------

const photoExtensions = new Set(["jpg", "jpeg", "png", "webp", "heic", "heif"]);
const otherImageExtensions = new Set(["gif", "bmp", "tif", "tiff", "svg", "ico", "avif"]);
const videoExtensions = new Set(["mp4", "mov", "m4v", "avi", "mkv", "webm", "mpg", "mpeg", "3gp"]);
const audioExtensions = new Set(["mp3", "m4a", "wav", "aac", "caf", "ogg", "flac", "aif", "aiff", "amr"]);

export type ResourceKind =
  | "photo"
  | "image_unsupported"
  | "video"
  | "audio"
  | "pdf"
  | "file";

export function extensionOf(path: string) {
  const name = path.split("/").at(-1) ?? "";
  const dot = name.lastIndexOf(".");
  return dot > 0 ? name.slice(dot + 1).toLowerCase() : "";
}

export function classifyFile(path: string): ResourceKind {
  const extension = extensionOf(path);
  if (photoExtensions.has(extension)) return "photo";
  if (otherImageExtensions.has(extension)) return "image_unsupported";
  if (videoExtensions.has(extension)) return "video";
  if (audioExtensions.has(extension)) return "audio";
  if (extension === "pdf") return "pdf";
  return "file";
}

export function baseName(path: string) {
  return path.split("/").at(-1) ?? path;
}

export function dirName(path: string) {
  const index = path.lastIndexOf("/");
  return index < 0 ? "" : path.slice(0, index);
}

export function stem(path: string) {
  const name = baseName(path);
  const dot = name.lastIndexOf(".");
  return dot > 0 ? name.slice(0, dot) : name;
}

/** Joins and cleans a relative reference against a folder, or null if it leaves the archive. */
export function resolvePath(folder: string, reference: string): string | null {
  const parts = (reference.startsWith("/") ? [] : folder.split("/").filter(Boolean));
  for (const segment of reference.split("/")) {
    if (segment === "" || segment === ".") continue;
    if (segment === "..") {
      if (parts.length === 0) return null;
      parts.pop();
    } else parts.push(segment);
  }
  return parts.join("/").normalize("NFC");
}

function decodeReference(reference: string) {
  const withoutQuery = reference.split(/[?#]/)[0];
  try {
    return decodeURIComponent(withoutQuery);
  } catch {
    return withoutQuery;
  }
}

/** Looks up archive members by path, ignoring case, and by bare file name when it is unique. */
export class MemberIndex {
  private exact = new Map<string, ZipMember>();
  private lower = new Map<string, ZipMember>();
  private names = new Map<string, ZipMember[]>();

  constructor(members: ZipMember[]) {
    for (const member of members) {
      const key = `${member.container ?? ""}\u0000${member.path}`;
      this.exact.set(key, member);
      this.lower.set(key.toLowerCase(), member);
      const name = baseName(member.path).toLowerCase();
      this.names.set(name, [...(this.names.get(name) ?? []), member]);
    }
  }

  resolve(
    from: ZipMember,
    reference: string,
  ): ZipMember | undefined {
    const decoded = decodeReference(reference.trim()).replaceAll("\\", "/");
    if (!decoded) return undefined;
    const container = from.container ?? "";
    const relative = resolvePath(dirName(from.path), decoded);
    const candidates = [relative, resolvePath("", decoded)];
    for (const path of candidates) {
      if (!path) continue;
      const key = `${container}\u0000${path}`;
      const found = this.exact.get(key) ?? this.lower.get(key.toLowerCase());
      if (found) return found;
    }
    if (!decoded.includes("/")) {
      const matches = this.names.get(decoded.normalize("NFC").toLowerCase()) ?? [];
      const inContainer = matches.filter((match) => (match.container ?? "") === container);
      if (inContainer.length === 1) return inContainer[0];
    }
    return undefined;
  }
}

export type ResolvedResources = {
  photos: ImportResource[];
  skipped: SkippedResource[];
  warnings: string[];
};

/**
 * Finds the files a note refers to. Photos become resources for the Entry; videos, audio,
 * PDFs, and other files are counted as not imported, because Entries hold photos only.
 */
export function resolveResources(
  index: MemberIndex,
  note: ZipMember,
  images: { src: string; alt: string }[],
  extraSkipped: Map<string, number> = new Map(),
): ResolvedResources {
  const photos: ImportResource[] = [];
  const skipped = new Map(extraSkipped);
  const warnings: string[] = [];
  const seen = new Set<string>();
  const bump = (kind: string) => skipped.set(kind, (skipped.get(kind) ?? 0) + 1);
  for (const image of images) {
    const member = index.resolve(note, image.src);
    if (!member) {
      warnings.push(importWarnings.photoMissing);
      continue;
    }
    const key = `${member.container ?? ""}|${member.path}`;
    if (seen.has(key)) continue;
    seen.add(key);
    const kind = classifyFile(member.path);
    if (kind !== "photo") {
      bump(kind);
      continue;
    }
    if (member.size > importLimits.maxPhotoBytes) {
      bump("photo_too_large");
      warnings.push(importWarnings.photoTooLarge);
      continue;
    }
    if (photos.length >= importLimits.maxPhotosPerEntry) {
      bump("photo_limit");
      warnings.push(importWarnings.photoLimit);
      continue;
    }
    photos.push({
      byteSize: member.size,
      ...(member.container ? { container: member.container } : {}),
      key,
      originalFilename: baseName(member.path),
      zipPath: member.path,
    });
  }
  return {
    photos,
    skipped: [...skipped].map(([kind, count]) => ({ count, kind })),
    warnings: [...new Set(warnings)],
  };
}

/** Whether an archive's files all share one leading folder, and which. */
export function commonRoot(paths: string[]): string {
  if (paths.length === 0) return "";
  const first = paths[0].split("/")[0];
  return paths.every((path) => path.includes("/") && path.split("/")[0] === first)
    ? first
    : "";
}

export function fileTimeIso(member: ZipMember, exclude: Set<number>): string | null {
  if (!member.modified) return null;
  const minute = Math.floor(member.modified.getTime() / 60_000);
  if (exclude.has(minute)) return null;
  return member.modified.toISOString();
}
