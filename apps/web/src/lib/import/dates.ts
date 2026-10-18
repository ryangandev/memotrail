import {
  validTimezone,
  validateOccurrence,
  wallTimeToISO,
  type Occurrence,
} from "@/lib/data/occurrence";
import type { ImportDate } from "./types";

const monthNames = [
  "january",
  "february",
  "march",
  "april",
  "may",
  "june",
  "july",
  "august",
  "september",
  "october",
  "november",
  "december",
];
const monthPattern =
  "(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)";
const weekdayPattern =
  "(?:(?:mon|tue|wed|thu|fri|sat|sun)[a-z]*\\.?,?\\s+)?";

function monthNumber(name: string) {
  const prefix = name.toLowerCase().slice(0, 3);
  const index = monthNames.findIndex((month) => month.startsWith(prefix));
  return index < 0 ? null : index + 1;
}

const pad = (value: number, length = 2) => String(value).padStart(length, "0");

function validCalendarDay(year: number, month: number, day: number) {
  if (year < 1000 || year > 2999 || month < 1 || month > 12 || day < 1)
    return false;
  const date = new Date(Date.UTC(year, month - 1, day));
  return (
    date.getUTCFullYear() === year &&
    date.getUTCMonth() === month - 1 &&
    date.getUTCDate() === day
  );
}

function dayText(year: number, month: number, day: number) {
  return validCalendarDay(year, month, day)
    ? `${pad(year, 4)}-${pad(month)}-${pad(day)}`
    : null;
}

/** "3:45 PM", "15:45", or "3 PM" as hours and minutes. */
function parseClock(text: string): { hour: number; minute: number } | null {
  const match = /^(\d{1,2})(?::(\d{2}))?(?::\d{2})?\s*([ap])?\.?m?\.?$/i.exec(
    text.trim(),
  );
  if (!match) return null;
  let hour = Number(match[1]);
  const minute = match[2] ? Number(match[2]) : 0;
  const meridiem = match[3]?.toLowerCase();
  if (minute > 59) return null;
  if (meridiem) {
    if (hour < 1 || hour > 12) return null;
    hour = (hour % 12) + (meridiem === "p" ? 12 : 0);
  } else if (hour > 23) return null;
  return { hour, minute };
}

/** "(GMT-7)" or "GMT+5:30" as minutes east of UTC. */
function parseGmtOffset(text: string): number | null {
  const match = /^\(?\s*(?:GMT|UTC)\s*([+-])(\d{1,2})(?::?(\d{2}))?\s*\)?$/i.exec(
    text.trim(),
  );
  if (!match) return null;
  const minutes = Number(match[2]) * 60 + Number(match[3] ?? 0);
  return (match[1] === "-" ? -1 : 1) * minutes;
}

function withClock(
  day: string,
  clockText: string | undefined,
  offsetText: string | undefined,
): ImportDate {
  if (!clockText) return { precision: "day", local: day };
  const clock = parseClock(clockText);
  if (!clock) return { precision: "day", local: day };
  const local = `${day}T${pad(clock.hour)}:${pad(clock.minute)}:00`;
  const offset = offsetText ? parseGmtOffset(offsetText) : null;
  if (offset !== null) {
    const instant = new Date(Date.parse(`${local}Z`) - offset * 60_000);
    return { precision: "exact", instant: instant.toISOString() };
  }
  return { precision: "exact", local };
}

/**
 * Reads one date the way English-language apps print it: "October 18, 2026", "Sunday,
 * October 18, 2026 at 3:45 PM", "18 October 2026", "October 2026", "2026-10-18",
 * "2026-10-18 15:45", an ISO instant with an offset, and "10/18/2026" when only one reading
 * is possible. Anything else is null, because a guessed date is worse than no date.
 */
export function parseDateText(input: string): ImportDate | null {
  const text = input
    .replace(/[  ]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  if (!text) return null;

  // 2026-10-18T15:45:00-07:00, with a zone designator: an instant.
  const instant =
    /^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?\s*(Z|[+-]\d{2}:?\d{2})$/i.exec(
      text,
    );
  if (instant) {
    const day = dayText(Number(instant[1]), Number(instant[2]), Number(instant[3]));
    const parsed = Date.parse(
      `${instant[1]}-${instant[2]}-${instant[3]}T${instant[4]}:${instant[5]}:${instant[6] ?? "00"}${
        instant[7].toUpperCase() === "Z"
          ? "Z"
          : `${instant[7].slice(0, 3)}:${instant[7].slice(-2)}`
      }`,
    );
    if (day && Number.isFinite(parsed))
      return { precision: "exact", instant: new Date(parsed).toISOString() };
    return null;
  }

  // 2026-10-18, 2026/10/18, 2026.10.18, optionally followed by a time.
  const numeric =
    /^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?:[T ,]+(\d{1,2}(?::\d{2})(?::\d{2})?(?:\s*[ap]\.?m\.?)?))?$/i.exec(
      text,
    );
  if (numeric) {
    const day = dayText(Number(numeric[1]), Number(numeric[2]), Number(numeric[3]));
    return day ? withClock(day, numeric[4], undefined) : null;
  }

  // 2026-10 and 2026.
  const monthOnly = /^(\d{4})-(\d{2})$/.exec(text);
  if (monthOnly && validCalendarDay(Number(monthOnly[1]), Number(monthOnly[2]), 1))
    return { precision: "month", local: `${monthOnly[1]}-${monthOnly[2]}` };
  if (/^\d{4}$/.test(text) && Number(text) >= 1000 && Number(text) <= 2999)
    return { precision: "year", local: text };

  // 10/18/2026 and 18/10/2026, only when exactly one reading is a real date.
  const slashed =
    /^(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})(?:[, ]+(\d{1,2}(?::\d{2})(?::\d{2})?(?:\s*[ap]\.?m\.?)?))?$/i.exec(
      text,
    );
  if (slashed) {
    const first = Number(slashed[1]);
    const second = Number(slashed[2]);
    const year = Number(slashed[3]);
    const monthFirst = dayText(year, first, second);
    const dayFirst = dayText(year, second, first);
    if (monthFirst && dayFirst && first !== second) return null;
    const day = monthFirst ?? dayFirst;
    return day ? withClock(day, slashed[4], undefined) : null;
  }

  // The tail may carry a zone: "(GMT-7)".
  let body = text;
  let offsetText: string | undefined;
  const zone = /\s*(\((?:GMT|UTC)[^)]*\)|(?:GMT|UTC)[+-]\d{1,2}(?::?\d{2})?)$/i.exec(
    body,
  );
  if (zone) {
    offsetText = zone[1];
    body = body.slice(0, zone.index).trim();
  } else {
    body = body.replace(/\s*\([A-Za-z ]{2,40}\)$/, "").trim();
  }

  // Month D, YYYY [at] [time]
  const monthFirst = new RegExp(
    `^${weekdayPattern}${monthPattern}\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?,?\\s+(\\d{4})(?:,?\\s+(?:at\\s+)?(\\d{1,2}(?::\\d{2})(?::\\d{2})?(?:\\s*[ap]\\.?m\\.?)?|\\d{1,2}\\s*[ap]\\.?m\\.?))?$`,
    "i",
  ).exec(body);
  if (monthFirst) {
    const month = monthNumber(monthFirst[1]);
    const day = month
      ? dayText(Number(monthFirst[3]), month, Number(monthFirst[2]))
      : null;
    return day ? withClock(day, monthFirst[4], offsetText) : null;
  }

  // D Month YYYY [at] [time]
  const dayFirst = new RegExp(
    `^${weekdayPattern}(\\d{1,2})(?:st|nd|rd|th)?\\s+${monthPattern}\\.?,?\\s+(\\d{4})(?:,?\\s+(?:at\\s+)?(\\d{1,2}(?::\\d{2})(?::\\d{2})?(?:\\s*[ap]\\.?m\\.?)?|\\d{1,2}\\s*[ap]\\.?m\\.?))?$`,
    "i",
  ).exec(body);
  if (dayFirst) {
    const month = monthNumber(dayFirst[2]);
    const day = month
      ? dayText(Number(dayFirst[3]), month, Number(dayFirst[1]))
      : null;
    return day ? withClock(day, dayFirst[4], offsetText) : null;
  }

  // Month YYYY
  const monthYear = new RegExp(`^${monthPattern}\\.?,?\\s+(\\d{4})$`, "i").exec(
    body,
  );
  if (monthYear) {
    const month = monthNumber(monthYear[1]);
    return month && validCalendarDay(Number(monthYear[2]), month, 1)
      ? { precision: "month", local: `${monthYear[2]}-${pad(month)}` }
      : null;
  }
  return null;
}

/**
 * A Notion date property: one date, or two joined by an arrow. A range keeps its days and
 * drops times, because the range precision is a calendar span.
 */
export function parseDatePropertyText(input: string): ImportDate | null {
  const parts = input.split(/\s*(?:→|->|—|–| to )\s*/i).filter(Boolean);
  if (parts.length === 2) {
    const start = parseDateText(parts[0]);
    const end = parseDateText(parts[1]);
    if (!start || !end) return null;
    const startDay = calendarDayOf(start);
    const endDay = calendarDayOf(end);
    if (!startDay || !endDay || endDay < startDay) return null;
    return startDay === endDay
      ? start
      : { precision: "range", local: startDay, localEnd: endDay };
  }
  return parts.length === 1 ? parseDateText(parts[0]) : null;
}

function calendarDayOf(date: ImportDate): string | null {
  if ("instant" in date) return date.instant.slice(0, 10);
  if (date.precision === "unknown" || date.precision === "range") return null;
  if (date.precision === "year") return `${date.local}-01-01`;
  if (date.precision === "month") return `${date.local}-01`;
  return date.local.slice(0, 10);
}

/** A title that is only a date names the day, so it becomes the date and the title is dropped. */
export function dateFromTitle(title: string): ImportDate | null {
  const text = title.trim();
  if (!text || text.length > 60) return null;
  return parseDateText(text);
}

/** A file name that starts with a date, such as "2024-05-12 Trip.md" or "20240512 notes". */
export function dateFromFileName(name: string): ImportDate | null {
  const base = name.replace(/\.[A-Za-z0-9]{1,5}$/, "").trim();
  const dashed = /^(\d{4})[-_.](\d{2})[-_.](\d{2})(?!\d)/.exec(base);
  const compact = /^(\d{4})(\d{2})(\d{2})(?!\d)/.exec(base);
  const match = dashed ?? compact;
  if (!match) return null;
  const day = dayText(Number(match[1]), Number(match[2]), Number(match[3]));
  return day ? { precision: "day", local: day } : null;
}

/** Whether a file time can stand for when something was written. */
export function plausibleFileTime(
  time: Date | string | null,
  now = new Date(),
): boolean {
  if (!time) return false;
  const value = typeof time === "string" ? new Date(time) : time;
  const ms = value.getTime();
  return (
    Number.isFinite(ms) &&
    ms >= Date.UTC(1990, 0, 1) &&
    ms <= now.getTime() &&
    value.getUTCFullYear() >= 1990
  );
}

/**
 * The file times in an archive are often all the moment of the export. When most files share
 * one minute, those times say nothing about when anything was written, so they are dropped.
 */
export function exportTimeCluster(times: (Date | null)[]): Set<number> {
  const buckets = new Map<number, number>();
  let counted = 0;
  for (const time of times) {
    if (!time || !Number.isFinite(time.getTime())) continue;
    const bucket = Math.floor(time.getTime() / 60_000);
    buckets.set(bucket, (buckets.get(bucket) ?? 0) + 1);
    counted += 1;
  }
  let modal: [number, number] | null = null;
  for (const entry of buckets) if (!modal || entry[1] > modal[1]) modal = entry;
  const clustered = new Set<number>();
  if (modal && counted >= 3 && modal[1] * 2 > counted) {
    for (const offset of [-1, 0, 1]) clustered.add(modal[0] + offset);
  }
  return clustered;
}

export type ResolvedImportDate = {
  occurredStart: string | null;
  occurredEnd: string | null;
  occurredTimezone: string;
  occurredLabel: string | null;
  datePrecision: Occurrence["datePrecision"];
};

export type DateResolutionOptions = {
  /** Zone for dates that carry none. */
  timezone: string;
  undated: "leave" | "file_time";
  fileModifiedAt: string | null;
};

const unknownDate = (
  timezone: string,
  label: string | null,
): ResolvedImportDate => ({
  datePrecision: "unknown",
  occurredEnd: null,
  occurredLabel: label,
  occurredStart: null,
  occurredTimezone: timezone,
});

/**
 * Turns the date a source gave into the stored fields. A day, month, or year is noon in the
 * zone, the way the editor stores it. A date that cannot be read stays unknown, with the text
 * the source showed kept as its description.
 */
export function resolveImportDate(
  date: ImportDate,
  options: DateResolutionOptions,
): ResolvedImportDate {
  const fallbackZone = validTimezone(options.timezone) ? options.timezone : "UTC";
  const result = resolveKnownDate(date, fallbackZone);
  if (result) {
    const error = validateOccurrence({
      datePrecision: result.datePrecision,
      occurredAt: result.occurredStart,
      occurredEnd: result.occurredEnd,
      occurredLabel: result.occurredLabel,
      occurredTimezone: result.occurredTimezone,
    });
    if (!error) return result;
  }
  const label =
    date.precision === "unknown" && date.label
      ? date.label.slice(0, 200)
      : null;
  if (
    options.undated === "file_time" &&
    options.fileModifiedAt &&
    plausibleFileTime(options.fileModifiedAt)
  ) {
    return {
      datePrecision: "exact",
      occurredEnd: null,
      occurredLabel: null,
      occurredStart: new Date(options.fileModifiedAt).toISOString(),
      occurredTimezone: fallbackZone,
    };
  }
  return unknownDate(fallbackZone, label);
}

function resolveKnownDate(
  date: ImportDate,
  fallbackZone: string,
): ResolvedImportDate | null {
  if (date.precision === "unknown") return null;
  const zoneOf = (zone: string | undefined) =>
    zone && validTimezone(zone) ? zone : fallbackZone;
  const finish = (
    precision: ResolvedImportDate["datePrecision"],
    start: string | null,
    end: string | null,
    timezone: string,
  ): ResolvedImportDate | null =>
    start
      ? {
          datePrecision: precision,
          occurredEnd: end,
          occurredLabel: null,
          occurredStart: start,
          occurredTimezone: timezone,
        }
      : null;

  if (date.precision === "exact") {
    if ("instant" in date) {
      const ms = Date.parse(date.instant);
      return Number.isFinite(ms)
        ? finish("exact", new Date(ms).toISOString(), null, zoneOf(date.timezone))
        : null;
    }
    const zone = fallbackZone;
    const start = wallTimeToISO(date.local, zone);
    if (start) return finish("exact", start, null, zone);
    // A time that does not exist in the zone still has a real day.
    const dayOnly = wallTimeToISO(`${date.local.slice(0, 10)}T12:00:00`, zone);
    return finish("day", dayOnly, null, zone);
  }
  const zone = zoneOf(date.timezone);
  const noon = (local: string) => wallTimeToISO(`${local}T12:00:00`, zone);
  if (date.precision === "day") return finish("day", noon(date.local), null, zone);
  if (date.precision === "month")
    return finish("month", noon(`${date.local}-01`), null, zone);
  if (date.precision === "year")
    return finish("year", noon(`${date.local}-01-01`), null, zone);
  if (date.precision !== "range") return null;
  const start = noon(date.local);
  const end = noon(date.localEnd);
  return start && end ? finish("range", start, end, zone) : null;
}
