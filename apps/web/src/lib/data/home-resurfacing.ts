import { parseHomeEntry, type HomeEntry } from "./home-entry";

export type HomeResurfacingKind = "from_your_archive" | "on_this_day";

export type HomeResurfacedMemory = Omit<
  HomeEntry,
  "inboxStatus" | "occurredStart"
> & {
  inboxStatus: "organized";
  occurredStart: string;
  resurfacingKind: HomeResurfacingKind;
  yearsAgo: number | null;
};

export function parseHomeResurfacedMemory(
  value: unknown,
): HomeResurfacedMemory | null {
  if (!Array.isArray(value) || value.length > 1) {
    return null;
  }

  if (value.length === 0) {
    return null;
  }

  const item = value[0];
  const entry = parseHomeEntry(item);

  if (
    !entry ||
    !isRecord(item) ||
    entry.inboxStatus !== "organized" ||
    entry.occurredStart === null ||
    (item.resurfacing_kind !== "on_this_day" &&
      item.resurfacing_kind !== "from_your_archive")
  ) {
    return null;
  }

  const yearsAgo = item.years_ago;
  let normalizedYearsAgo: number | null;

  if (item.resurfacing_kind === "on_this_day") {
    if (
      typeof yearsAgo !== "number" ||
      !Number.isSafeInteger(yearsAgo) ||
      yearsAgo < 1
    ) {
      return null;
    }
    normalizedYearsAgo = yearsAgo;
  } else {
    if (yearsAgo !== null) {
      return null;
    }
    normalizedYearsAgo = null;
  }

  return {
    ...entry,
    inboxStatus: "organized",
    occurredStart: entry.occurredStart,
    resurfacingKind: item.resurfacing_kind,
    yearsAgo: normalizedYearsAgo,
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}
