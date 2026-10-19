export type Frontmatter = Record<string, string | string[]>;

function unquote(value: string) {
  const trimmed = value.trim();
  if (
    trimmed.length >= 2 &&
    ((trimmed.startsWith('"') && trimmed.endsWith('"')) ||
      (trimmed.startsWith("'") && trimmed.endsWith("'")))
  )
    return trimmed.slice(1, -1);
  return trimmed;
}

function splitInlineList(value: string): string[] {
  return value
    .slice(1, -1)
    .split(",")
    .map(unquote)
    .filter((item) => item.length > 0);
}

/**
 * Reads the YAML block at the top of a note. Only what notes apps write is understood: plain
 * `key: value` lines, quoted values, `[a, b]` lists, and `- item` lists. Anything else is
 * ignored, and a block that never closes is treated as ordinary text.
 */
export function splitFrontmatter(text: string): {
  data: Frontmatter;
  body: string;
} {
  const source = text.replace(/^﻿/, "");
  const opening = /^---[ \t]*\r?\n/.exec(source);
  if (!opening) return { body: source, data: {} };
  const rest = source.slice(opening[0].length);
  const closing = /^(?:---|\.\.\.)[ \t]*(?:\r?\n|$)/m.exec(rest);
  if (!closing) return { body: source, data: {} };

  const block = rest.slice(0, closing.index);
  const body = rest.slice(closing.index + closing[0].length);
  const data: Frontmatter = {};
  let listKey: string | null = null;
  for (const line of block.split(/\r?\n/)) {
    const item = /^\s+-\s+(.*)$/.exec(line) ?? /^-\s+(.*)$/.exec(line);
    if (item && listKey) {
      const current = data[listKey];
      const value = unquote(item[1]);
      data[listKey] = Array.isArray(current) ? [...current, value] : [value];
      continue;
    }
    const pair = /^([A-Za-z0-9_][A-Za-z0-9_ .-]*?)\s*:\s*(.*)$/.exec(line);
    if (!pair) {
      listKey = null;
      continue;
    }
    const key = pair[1].trim().toLowerCase();
    const value = pair[2].trim();
    if (value === "") {
      data[key] = [];
      listKey = key;
    } else if (value.startsWith("[") && value.endsWith("]")) {
      data[key] = splitInlineList(value);
      listKey = null;
    } else {
      data[key] = unquote(value);
      listKey = null;
    }
  }
  return { body, data };
}

/** The first value found under any of the names. */
export function frontmatterText(
  data: Frontmatter,
  names: readonly string[],
): string | null {
  for (const name of names) {
    const value = data[name];
    if (typeof value === "string" && value.trim()) return value.trim();
    if (Array.isArray(value) && value.length > 0 && value[0].trim())
      return value[0].trim();
  }
  return null;
}

/** Tags written as a list or as one comma or space separated line. */
export function frontmatterTags(data: Frontmatter): string[] {
  const names = ["tags", "tag", "keywords"];
  const result: string[] = [];
  for (const name of names) {
    const value = data[name];
    if (Array.isArray(value)) result.push(...value);
    else if (typeof value === "string")
      result.push(
        ...value
          .split(value.includes(",") ? /,/ : /\s+/)
          .map((item) => item.trim())
          .filter(Boolean),
      );
  }
  return result;
}
