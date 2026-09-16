import { entryBodyLimit } from "./inbox-input";

export const entryRichTextMetadataKey = "body_rich";

const maximumDocumentBytes = 250_000;
const maximumDocumentDepth = 24;
const maximumDocumentNodes = 4_000;
const maximumLinkLength = 2_048;

const blockNodeTypes = new Set([
  "blockquote",
  "bulletList",
  "codeBlock",
  "orderedList",
  "paragraph",
]);
const markTypes = new Set([
  "bold",
  "code",
  "italic",
  "link",
  "strike",
  "underline",
]);

export type RichTextMark = {
  attrs?: Record<string, unknown>;
  type: string;
};

export type RichTextNode = {
  attrs?: Record<string, unknown>;
  content?: RichTextNode[];
  marks?: RichTextMark[];
  text?: string;
  type: string;
};

export type RichTextDocument = RichTextNode & {
  content: RichTextNode[];
  type: "doc";
};

export type EntryRichText = {
  document: RichTextDocument;
  text: string;
  version: 1;
};

export function plainTextDocument(text: string): RichTextDocument {
  return {
    content: text.split("\n").map((line) => ({
      ...(line ? { content: [{ text: line, type: "text" }] } : {}),
      type: "paragraph",
    })),
    type: "doc",
  };
}

export function plainTextFromDocument(document: RichTextDocument) {
  return nodeText(document);
}

export function createEntryRichText(
  document: RichTextDocument,
): EntryRichText | null {
  const text = plainTextFromDocument(document);
  const value: EntryRichText = { document, text, version: 1 };

  return isEntryRichText(value) ? value : null;
}

export function isEntryRichText(
  value: unknown,
  expectedText?: string,
): value is EntryRichText {
  if (!isRecord(value)) return false;
  if (
    value.version !== 1 ||
    typeof value.text !== "string" ||
    value.text.length > entryBodyLimit ||
    (expectedText !== undefined && value.text !== expectedText) ||
    !isRecord(value.document)
  ) {
    return false;
  }

  let bytes = 0;
  try {
    bytes = JSON.stringify(value.document).length;
  } catch {
    return false;
  }
  if (bytes > maximumDocumentBytes) return false;

  const state = { nodes: 0 };
  if (!isRichTextNode(value.document, null, 0, state)) return false;
  const document = value.document as RichTextDocument;

  return plainTextFromDocument(document) === value.text;
}

export function entryRichTextFromMetadata(
  metadata: unknown,
  body: string,
): EntryRichText | null {
  if (!isRecord(metadata)) return null;
  const candidate = metadata[entryRichTextMetadataKey];
  return isEntryRichText(candidate, body) ? candidate : null;
}

export function metadataWithEntryRichText(value: EntryRichText | null) {
  return value ? { [entryRichTextMetadataKey]: value } : {};
}

export function parseEntryRichTextJson(
  value: unknown,
  expectedText: string,
): EntryRichText | null {
  if (
    typeof value !== "string" ||
    value.length > maximumDocumentBytes + entryBodyLimit
  ) {
    return null;
  }

  try {
    const parsed = JSON.parse(value) as unknown;
    return isEntryRichText(parsed, expectedText) ? parsed : null;
  } catch {
    return null;
  }
}

function isRichTextNode(
  value: unknown,
  parentType: string | null,
  depth: number,
  state: { nodes: number },
): value is RichTextNode {
  if (!isRecord(value) || depth > maximumDocumentDepth) return false;
  state.nodes += 1;
  if (state.nodes > maximumDocumentNodes || typeof value.type !== "string")
    return false;

  const type = value.type;
  if (!allowedChild(parentType, type) || !validNodeAttrs(type, value.attrs))
    return false;

  if (type === "text") {
    return (
      typeof value.text === "string" &&
      value.text.length > 0 &&
      value.content === undefined &&
      validMarks(value.marks)
    );
  }

  if (type === "hardBreak") {
    return (
      value.text === undefined &&
      value.content === undefined &&
      value.marks === undefined
    );
  }

  if (value.text !== undefined || value.marks !== undefined) {
    return false;
  }

  const content = value.content === undefined ? [] : value.content;
  if (!Array.isArray(content)) return false;
  if (
    value.content === undefined &&
    type !== "paragraph" &&
    type !== "codeBlock"
  ) {
    return false;
  }

  if (type === "doc" && content.length === 0) return false;
  if (
    (type === "bulletList" || type === "orderedList") &&
    content.length === 0
  ) {
    return false;
  }

  return content.every((child) =>
    isRichTextNode(child, type, depth + 1, state),
  );
}

function allowedChild(parentType: string | null, childType: string) {
  if (parentType === null) return childType === "doc";
  if (parentType === "doc") return blockNodeTypes.has(childType);
  if (parentType === "paragraph")
    return childType === "text" || childType === "hardBreak";
  if (parentType === "codeBlock") return childType === "text";
  if (parentType === "bulletList" || parentType === "orderedList")
    return childType === "listItem";
  if (parentType === "blockquote") return blockNodeTypes.has(childType);
  if (parentType === "listItem")
    return childType === "paragraph" || blockNodeTypes.has(childType);
  return false;
}

function validNodeAttrs(type: string, attrs: unknown) {
  if (attrs === undefined) return true;
  if (!isRecord(attrs)) return false;

  const allowedKeys =
    type === "orderedList"
      ? new Set(["start", "type"])
      : type === "bulletList"
        ? new Set(["type"])
        : type === "codeBlock"
          ? new Set(["language"])
          : new Set<string>();

  return Object.entries(attrs).every(
    ([key, value]) =>
      allowedKeys.has(key) &&
      (value === null ||
        (key === "start"
          ? Number.isInteger(value) && (value as number) > 0
          : typeof value === "string" && value.length <= 100)),
  );
}

function validMarks(value: unknown) {
  if (value === undefined) return true;
  if (!Array.isArray(value)) return false;

  return value.every((mark) => {
    if (!isRecord(mark) || typeof mark.type !== "string") return false;
    if (!markTypes.has(mark.type)) return false;

    if (mark.type !== "link") {
      return (
        mark.attrs === undefined ||
        (isRecord(mark.attrs) && Object.keys(mark.attrs).length === 0)
      );
    }

    if (!isRecord(mark.attrs) || !safeLink(mark.attrs.href)) return false;
    const allowedKeys = new Set(["class", "href", "rel", "target", "title"]);
    return Object.entries(mark.attrs).every(
      ([key, item]) =>
        allowedKeys.has(key) &&
        (item === null ||
          (typeof item === "string" && item.length <= maximumLinkLength)),
    );
  });
}

function safeLink(value: unknown) {
  if (typeof value !== "string" || value.length > maximumLinkLength)
    return false;
  try {
    const url = new URL(value);
    return ["http:", "https:", "mailto:", "tel:"].includes(url.protocol);
  } catch {
    return false;
  }
}

function nodeText(node: RichTextNode): string {
  if (node.type === "text") return node.text ?? "";
  if (node.type === "hardBreak") return "\n";

  const children = node.content ?? [];
  const separator = [
    "blockquote",
    "bulletList",
    "doc",
    "listItem",
    "orderedList",
  ].includes(node.type)
    ? "\n"
    : "";
  return children.map(nodeText).join(separator);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
