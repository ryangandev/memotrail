// Small helpers shared by the resolver and the platform writers.

export function isObject(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function isUnit(value) {
  return Number.isFinite(value) && value >= 0 && value <= 1;
}

export function hexString(channels) {
  return `#${channels
    .map((channel) => channel.toString(16).padStart(2, "0"))
    .join("")
    .toUpperCase()}`;
}

export function describePath(path) {
  const parts = Array.isArray(path) ? path : path.split(".");
  return parts.length === 0 || parts[0] === ""
    ? "The token document"
    : `{${parts.join(".")}}`;
}

export function kebabCase(value) {
  return value.replace(/([a-z0-9])([A-Z])/g, "$1-$2").toLowerCase();
}

// Joins path segments into one camelCase identifier: ["disabled", "opacity"] -> disabledOpacity.
export function camelCase(segments) {
  return segments
    .map((segment, index) =>
      index === 0 ? segment : segment[0].toUpperCase() + segment.slice(1),
    )
    .join("");
}

export function pascalCase(value) {
  return value[0].toUpperCase() + value.slice(1);
}

export function indent(lines, spaces = 2) {
  const prefix = " ".repeat(spaces);
  return lines.map((line) => (line ? `${prefix}${line}` : line)).join("\n");
}

export function setPath(target, [key, ...rest], value) {
  if (rest.length === 0) {
    target[key] = value;
    return;
  }
  target[key] ??= {};
  setPath(target[key], rest, value);
}

export function aliasPath(value) {
  return typeof value === "string" ? value.match(/^\{([^{}]+)\}$/)?.[1] : null;
}

export function deepEqual(a, b) {
  return JSON.stringify(a) === JSON.stringify(b);
}

// Formats a number the way people write it: no trailing zeros or binary noise.
export function formatNumber(value) {
  return String(Number(value.toFixed(6)));
}
