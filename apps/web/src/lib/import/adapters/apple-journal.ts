import { parseFragment, serializeOuter } from "parse5";
import type { DefaultTreeAdapterMap } from "parse5";
import { htmlToBlocks, newContext } from "../convert-html";
import { dateFromFileName, exportTimeCluster, parseDateText } from "../dates";
import { importLimits } from "../limits";
import { importWarnings } from "../types";
import { ImportError, type ZipArchive, type ZipMember } from "../zip";
import {
  MemberIndex,
  baseName,
  fileTimeIso,
  finalizeDraft,
  resolveResources,
  stem,
  type ImportAdapter,
  type ScanItem,
} from "./shared";

type Node = DefaultTreeAdapterMap["node"];
type Element = DefaultTreeAdapterMap["element"];

const entryFile = /(^|\/)Entries\/[^/]+\.html?$/i;

const isElement = (node: Node): node is Element => "tagName" in node;
const isText = (node: Node): node is DefaultTreeAdapterMap["textNode"] =>
  node.nodeName === "#text";

function classes(element: Element): string {
  return element.attrs.find((attr) => attr.name === "class")?.value ?? "";
}

function attribute(element: Element, name: string) {
  return element.attrs.find((attr) => attr.name === name)?.value;
}

function walk(nodes: Node[], visit: (element: Element) => boolean | void) {
  for (const node of nodes) {
    if (!isElement(node)) continue;
    if (visit(node) === false) continue;
    walk(node.childNodes, visit);
  }
}

function textOf(node: Node): string {
  if (isText(node)) return node.value;
  if (!isElement(node)) return "";
  if (["script", "style", "head", "title"].includes(node.tagName)) return "";
  const inner = node.childNodes.map(textOf).join("");
  return node.tagName === "br" ||
    ["p", "div", "li", "h1", "h2", "h3", "h4", "h5", "h6"].includes(
      node.tagName,
    )
    ? `${inner}\n`
    : inner;
}

const clean = (text: string) => text.replace(/\s+/g, " ").trim();

const dateClass = /pageheader|entrydate|(^|[\s_-])date([\s_-]|$)/i;
const titleClass = /(^|[\s_-])title([\s_-]|$)/i;
const bodyClass = /bodytext|entrybody|(^|[\s_-])body([\s_-]|$)/i;
// Lines Apple's export adds around the writing: State of Mind, place, people, activity.
const metadataClass =
  /state.?of.?mind|location|place|contact|motion|activity|workout|podcast|music|third.?party/i;
const mapClass = /map|snapshot/i;

type Parsed = {
  titleText: string | null;
  dateText: string | null;
  bodyHtml: string;
  metadataLines: string[];
  images: { src: string; alt: string }[];
  skipped: Map<string, number>;
};

/**
 * Reads one Journal entry page. The markup is not documented, so this looks for the pieces by
 * the class names third-party importers report and degrades to plain text when it finds none:
 * the date and title are taken out of the page, the writing is the body, and anything that
 * looks like State of Mind or a place is kept as a plain line after it.
 */
function parseEntryPage(html: string): Parsed {
  const fragment = parseFragment(html);
  let dateEl = null as Element | null;
  let titleEl = null as Element | null;
  const bodyEls: Element[] = [];
  const metadataEls: Element[] = [];
  const mediaImages: { src: string; alt: string }[] = [];
  const skipped = new Map<string, number>();
  let timeAttribute = null as string | null;

  const inside = (outer: Element, inner: Element) => {
    let found = false;
    walk(outer.childNodes, (element) => {
      if (element === inner) found = true;
    });
    return found;
  };

  walk(fragment.childNodes, (element) => {
    const name = classes(element);
    if (element.tagName === "time" && !timeAttribute)
      timeAttribute = attribute(element, "datetime") ?? null;
    if (!dateEl && dateClass.test(name)) {
      dateEl = element;
      return false;
    }
    if (!titleEl && titleClass.test(name) && !/sub/i.test(name)) {
      titleEl = element;
      return false;
    }
    if (
      bodyClass.test(name) &&
      !bodyEls.some((body) => inside(body, element))
    ) {
      bodyEls.push(element);
      return;
    }
    if (metadataClass.test(name)) {
      metadataEls.push(element);
      return false;
    }
    return;
  });

  // Pictures and other files can sit outside the writing, in a grid of their own.
  walk(fragment.childNodes, (element) => {
    const name = classes(element);
    if (element.tagName === "img") {
      const src = attribute(element, "src") ?? "";
      const alt = attribute(element, "alt") ?? "";
      if (!src || src.startsWith("data:")) return;
      if (mapClass.test(name) || mapClass.test(alt) || mapClass.test(src)) {
        skipped.set("map", (skipped.get("map") ?? 0) + 1);
        return;
      }
      mediaImages.push({ alt, src });
    } else if (element.tagName === "video" || element.tagName === "audio") {
      skipped.set(element.tagName, (skipped.get(element.tagName) ?? 0) + 1);
      return false;
    }
    return;
  });

  const withoutParts = (nodes: Node[]): Node[] =>
    nodes
      .filter((node) => node !== dateEl && node !== titleEl)
      .filter((node) => !(isElement(node) && metadataEls.includes(node)))
      .map((node) =>
        isElement(node)
          ? ({ ...node, childNodes: withoutParts(node.childNodes) } as Element)
          : node,
      );

  const bodyHtml =
    bodyEls.length > 0
      ? bodyEls.map((element) => serializeOuter(element)).join("\n")
      : withoutParts(fragment.childNodes)
          .map((node) =>
            isElement(node)
              ? serializeOuter(node)
              : isText(node)
                ? node.value
                : "",
          )
          .join("\n");

  const metadataLines: string[] = [];
  for (const element of metadataEls) {
    const line = clean(textOf(element));
    if (line && !metadataLines.includes(line)) metadataLines.push(line);
  }

  return {
    bodyHtml,
    dateText: dateEl ? clean(textOf(dateEl)) : timeAttribute,
    images: mediaImages,
    metadataLines,
    skipped,
    titleText: titleEl ? clean(textOf(titleEl)) : null,
  };
}

/**
 * An Apple Journal export: a folder (zipped) with an Entries folder of HTML files and a
 * Resources folder of photos. Dates are English; an entry whose date cannot be read stays
 * undated and the preview says so.
 */
export const appleJournalAdapter: ImportAdapter = {
  detect(archive) {
    const entries = archive.members.filter((member) =>
      entryFile.test(member.path),
    );
    if (entries.length === 0) return 0;
    const hasResources = archive.members.some((member) =>
      /(^|\/)Resources\//i.test(member.path),
    );
    return hasResources ? 0.9 : 0.6;
  },

  async *scan(archive) {
    const notes = archive.members
      .filter((member) => entryFile.test(member.path))
      .sort(
        (a, b) =>
          (a.container ?? "").localeCompare(b.container ?? "") ||
          a.path.localeCompare(b.path),
      );
    const index = new MemberIndex(archive.members);
    const clustered = exportTimeCluster(notes.map((note) => note.modified));
    for (const note of notes) yield* scanEntry(archive, index, note, clustered);
  },
};

async function* scanEntry(
  archive: ZipArchive,
  index: MemberIndex,
  note: ZipMember,
  clustered: Set<number>,
): AsyncGenerator<ScanItem> {
  const sourceKey = `entry:${baseName(note.path).toLowerCase()}`;
  let html: string;
  try {
    html = await archive.readText(note, importLimits.maxTextFileBytes);
  } catch (error) {
    if (error instanceof ImportError && error.code === "file_too_large") {
      yield {
        folderPath: [],
        kind: "skipped",
        reason: "file_too_large",
        sourceKey,
      };
      return;
    }
    throw error;
  }
  const parsed = parseEntryPage(html);
  const context = newContext(false);
  const blocks = htmlToBlocks(parsed.bodyHtml, context);
  // A picture inside the writing and one in the grid are the same file; resolution de-duplicates.
  const images = [...context.images, ...parsed.images];
  for (const [kind, count] of parsed.skipped)
    context.skipped.set(kind, (context.skipped.get(kind) ?? 0) + count);
  const resources = resolveResources(index, note, images, context.skipped);

  const date = parsed.dateText ? parseDateText(parsed.dateText) : null;
  const unparsed = Boolean(parsed.dateText) && !date;
  const fileTime = fileTimeIso(note, clustered);

  yield* finalizeDraft({
    blocks,
    date: date ?? {
      precision: "unknown",
      ...(unparsed ? { label: parsed.dateText!.slice(0, 200) } : {}),
    },
    fileModifiedAt: fileTime,
    fileNameDate: dateFromFileName(
      stem(note.path).replace(/^.*?(?=\d{4}[-_.]?\d{2}[-_.]?\d{2})/, ""),
    ),
    folderPath: [],
    photos: resources.photos,
    skipped: resources.skipped,
    source: "apple_journal",
    sourceKey,
    sourceModifiedAt: fileTime,
    tagNames: [],
    title: parsed.titleText,
    trailingLines: parsed.metadataLines,
    warnings: [
      ...resources.warnings,
      ...(unparsed ? [importWarnings.dateUnparsed] : []),
    ],
  });
}
