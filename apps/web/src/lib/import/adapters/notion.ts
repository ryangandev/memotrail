import { convertMarkdownNote } from "../convert-note";
import { exportTimeCluster, parseDatePropertyText } from "../dates";
import { importLimits } from "../limits";
import { paragraph, textNodes } from "../rich";
import { ImportError, type ZipArchive, type ZipMember } from "../zip";
import {
  MemberIndex,
  dirName,
  fileTimeIso,
  finalizeDraft,
  resolveResources,
  stem,
  type ImportAdapter,
  type ScanItem,
} from "./shared";

const notionId = /^(.*?)[ -]?([0-9a-f]{32})$/i;
const markdownFile = /\.md$/i;
const csvFile = /\.csv$/i;

/** Notion appends a 32 character id to every page and folder name. */
export function splitNotionName(name: string): {
  title: string;
  id: string | null;
} {
  const match = notionId.exec(name.trim());
  return match
    ? { id: match[2].toLowerCase(), title: match[1].trim() }
    : { id: null, title: name.trim() };
}

/** A folder name without its id. The export folder Notion adds around everything is dropped. */
function folderTitle(segment: string): string | null {
  if (/^Export-[0-9a-f-]{8,}/i.test(segment)) return null;
  return splitNotionName(segment).title || null;
}

/** Properties whose values are tags, in the names Notion databases usually give them. */
const tagPropertyNames = new Set([
  "tags",
  "tag",
  "labels",
  "label",
  "categories",
  "category",
]);

const propertyLine = /^([^:\n]{1,80}):[ \t]*(.*)$/;

/**
 * The `Key: value` lines Notion writes under a database row's title. Only the first block of
 * lines directly after the heading counts, and only when every line in it looks like one.
 */
export function splitProperties(markdown: string): {
  heading: string | null;
  properties: [string, string][];
  rest: string;
} {
  const lines = markdown.replace(/\r\n?/g, "\n").split("\n");
  let at = 0;
  while (at < lines.length && lines[at].trim() === "") at += 1;
  const headingMatch = /^#[ \t]+(.+?)[ \t]*#*[ \t]*$/.exec(lines[at] ?? "");
  if (!headingMatch) return { heading: null, properties: [], rest: markdown };
  const heading = headingMatch[1].trim();
  let cursor = at + 1;
  while (cursor < lines.length && lines[cursor].trim() === "") cursor += 1;
  const start = cursor;
  const block: [string, string][] = [];
  while (cursor < lines.length && lines[cursor].trim() !== "") {
    const match = propertyLine.exec(lines[cursor]);
    if (!match) return { heading, properties: [], rest: markdown };
    block.push([match[1].trim(), match[2].trim()]);
    cursor += 1;
  }
  if (block.length === 0 || start === cursor)
    return { heading, properties: [], rest: markdown };
  return { heading, properties: block, rest: lines.slice(cursor).join("\n") };
}

function csvKey(directory: string, name: string) {
  return `${directory}\u0000${splitNotionName(name.replace(/_all$/i, "")).title.toLowerCase()}`;
}

/**
 * A Notion "Markdown & CSV" export. Pages are Markdown files whose names end in a 32 character
 * id, which is the key that keeps a re-import from adding copies. Database rows carry their
 * properties as `Key: value` lines; a property that reads as a date can date the Entry, and a
 * Tags property becomes tags. Pages with no date property are undated, because the export has
 * no created or edited time.
 */
export const notionAdapter: ImportAdapter = {
  detect(archive) {
    const files = archive.members.filter(
      (member) => markdownFile.test(member.path) || csvFile.test(member.path),
    );
    if (files.length === 0) return 0;
    const withId = files.filter((member) =>
      notionId.test(stem(member.path)),
    ).length;
    if (withId === 0) return 0;
    return withId / files.length >= 0.5 ? 0.9 : 0.6;
  },

  async *scan(archive) {
    const notes = archive.members
      .filter((member) => markdownFile.test(member.path))
      .sort(
        (a, b) =>
          (a.container ?? "").localeCompare(b.container ?? "") ||
          a.offset - b.offset,
      );
    const index = new MemberIndex(archive.members);
    const databases = new Set(
      archive.members
        .filter((member) => csvFile.test(member.path))
        .map((member) => csvKey(dirName(member.path), stem(member.path))),
    );
    const clustered = exportTimeCluster(notes.map((note) => note.modified));
    for (const note of notes)
      yield* scanPage(archive, index, note, databases, clustered);
  },
};

async function* scanPage(
  archive: ZipArchive,
  index: MemberIndex,
  note: ZipMember,
  databases: Set<string>,
  clustered: Set<number>,
): AsyncGenerator<ScanItem> {
  const parts = dirName(note.path).split("/").filter(Boolean);
  const folderPath = parts
    .map(folderTitle)
    .filter((name): name is string => name !== null);
  const { id, title: nameTitle } = splitNotionName(stem(note.path));
  const sourceKey = id ?? note.path;

  let text: string;
  try {
    text = await archive.readText(note, importLimits.maxTextFileBytes);
  } catch (error) {
    if (error instanceof ImportError && error.code === "file_too_large") {
      yield {
        folderPath,
        kind: "skipped",
        reason: "file_too_large",
        sourceKey,
      };
      return;
    }
    throw error;
  }

  // A row of a database has a CSV with the database's name beside its folder.
  const folder = parts.at(-1);
  const isRow =
    folder !== undefined &&
    databases.has(csvKey(parts.slice(0, -1).join("/"), folder));
  const split = isRow
    ? splitProperties(text)
    : { heading: null, properties: [] as [string, string][], rest: text };
  const markdown =
    split.heading !== null && split.properties.length > 0
      ? `# ${split.heading}\n\n${split.rest}`
      : text;
  const converted = convertMarkdownNote(markdown, nameTitle, {
    collectHashtags: false,
  });

  const propertyLines = split.properties.map(([key, value]) =>
    paragraph(textNodes(value ? `${key}: ${value}` : `${key}:`)),
  );
  const resources = resolveResources(
    index,
    note,
    converted.images,
    converted.skipped,
  );
  if (
    converted.blocks.length === 0 &&
    propertyLines.length === 0 &&
    resources.photos.length === 0
  ) {
    // A page that only holds other pages is a folder, not an Entry.
    yield { folderPath, kind: "skipped", reason: "empty", sourceKey };
    return;
  }

  const dateProperties: Record<string, string> = {};
  const propertyTagNames: string[] = [];
  for (const [key, value] of split.properties) {
    if (tagPropertyNames.has(key.toLowerCase()) && value)
      propertyTagNames.push(
        ...value
          .split(",")
          .map((tag) => tag.trim())
          .filter(Boolean),
      );
    else if (value && parseDatePropertyText(value)) dateProperties[key] = value;
  }

  const fileTime = fileTimeIso(note, clustered);
  yield* finalizeDraft({
    blocks: [...propertyLines, ...converted.blocks],
    dateProperties,
    date: { precision: "unknown" },
    fileModifiedAt: fileTime,
    folderPath,
    photos: resources.photos,
    propertyTagNames,
    skipped: resources.skipped,
    source: "notion",
    sourceKey,
    sourceModifiedAt: fileTime,
    tagNames: [],
    title: converted.title,
    warnings: resources.warnings,
  });
}
