import { plainTextFromDocument } from "@/lib/data/rich-text";
import { convertMarkdownNote } from "../convert-note";
import { dateFromFileName, exportTimeCluster, parseDateText } from "../dates";
import { sha256Hex } from "../identity";
import { importLimits } from "../limits";
import { importWarnings, type ImportDate } from "../types";
import { ImportError, type ZipArchive, type ZipMember } from "../zip";
import {
  MemberIndex,
  baseName,
  commonRoot,
  dirName,
  fileTimeIso,
  finalizeDraft,
  resolveResources,
  stem,
  type ImportAdapter,
  type ScanItem,
} from "./shared";
import { docOf } from "../rich";
import {
  frontmatterTags,
  frontmatterText,
  splitFrontmatter,
} from "../frontmatter";

export const markdownExtension = /\.(md|markdown)$/i;

const dateNames = [
  "date",
  "created",
  "created_at",
  "createdat",
  "date created",
  "created on",
  "datetime",
  "day",
  "published",
];

/** The date a note's frontmatter states, or unknown with the text it used. */
export function frontmatterDate(data: Record<string, string | string[]>): {
  date: ImportDate;
  unparsed: boolean;
} {
  const text = frontmatterText(data, dateNames);
  if (!text) return { date: { precision: "unknown" }, unparsed: false };
  const parsed = parseDateText(text);
  return parsed
    ? { date: parsed, unparsed: false }
    : {
        date: { label: text.slice(0, 200), precision: "unknown" },
        unparsed: true,
      };
}

function normalizeForKey(text: string) {
  return text.replace(/\s+/g, " ").trim().toLowerCase();
}

/**
 * Markdown notes in a folder: Obsidian vaults, Apple Notes exports (macOS Tahoe and iOS 26
 * Markdown, or a third-party exporter), and anything else that writes .md files. A note's
 * date comes from its frontmatter, then its title, then its file name, and is otherwise
 * unknown; the file's own time is offered only when the person asks.
 */
export const markdownAdapter: ImportAdapter = {
  detect(archive) {
    return archive.members.some((member) => markdownExtension.test(member.path))
      ? 0.4
      : 0;
  },

  async *scan(archive, options) {
    const notes = archive.members
      .filter((member) => markdownExtension.test(member.path))
      .sort(
        (a, b) =>
          (a.container ?? "").localeCompare(b.container ?? "") ||
          a.offset - b.offset,
      );
    const index = new MemberIndex(archive.members);
    const root = commonRoot(
      archive.members
        .filter((member) => !member.container)
        .map((member) => member.path),
    );
    const clustered = exportTimeCluster(notes.map((note) => note.modified));
    for (const note of notes) {
      yield* scanNote(
        archive,
        index,
        note,
        root,
        clustered,
        options.source === "apple_notes" ? "apple_notes" : "markdown",
      );
    }
  },
};

async function* scanNote(
  archive: ZipArchive,
  index: MemberIndex,
  note: ZipMember,
  root: string,
  clustered: Set<number>,
  source: "markdown" | "apple_notes",
): AsyncGenerator<ScanItem> {
  // The folder an export was zipped from varies, so it is left out of the key.
  const relative =
    root && note.path.startsWith(`${root}/`)
      ? note.path.slice(root.length + 1)
      : note.path;
  const folderPath = dirName(note.path).split("/").filter(Boolean);
  let text: string;
  try {
    text = await archive.readText(note, importLimits.maxTextFileBytes);
  } catch (error) {
    if (error instanceof ImportError && error.code === "file_too_large") {
      yield {
        folderPath,
        kind: "skipped",
        reason: "file_too_large",
        sourceKey: relative,
      };
      return;
    }
    throw error;
  }

  const { data, body } = splitFrontmatter(text);
  const converted = convertMarkdownNote(body, stem(note.path), {
    collectHashtags: true,
    frontmatterTitle: frontmatterText(data, ["title"]),
  });
  const { date, unparsed } = frontmatterDate(data);
  const resources = resolveResources(
    index,
    note,
    converted.images,
    converted.skipped,
  );
  if (
    converted.titleSource === "fallback" &&
    converted.blocks.length === 0 &&
    resources.photos.length === 0
  ) {
    yield { folderPath, kind: "skipped", reason: "empty", sourceKey: relative };
    return;
  }
  const fileTime = fileTimeIso(note, clustered);

  const plain = plainTextFromDocument(docOf(converted.blocks));
  const explicitId = frontmatterText(data, ["id", "uuid"]);
  const sourceKey = explicitId
    ? `id:${explicitId}`
    : source === "apple_notes"
      ? `note:${sha256Hex(`${normalizeForKey(converted.title ?? "")}\n${normalizeForKey(plain)}`).slice(0, 32)}`
      : relative;

  yield* finalizeDraft({
    blocks: converted.blocks,
    date,
    fileModifiedAt: fileTime,
    fileNameDate: dateFromFileName(baseName(note.path)),
    folderPath,
    photos: resources.photos,
    skipped: resources.skipped,
    source,
    sourceCreatedAt: "instant" in date ? date.instant : null,
    sourceKey,
    sourceModifiedAt: fileTime,
    tagNames: [...frontmatterTags(data), ...converted.tags],
    title: converted.title,
    warnings: [
      ...resources.warnings,
      ...(unparsed ? [importWarnings.dateUnparsed] : []),
    ],
  });
}
