export const occurrencePrecisions = [
  "exact",
  "day",
  "month",
  "year",
  "approximate",
  "age",
  "range",
  "unknown",
] as const;
export type OccurrencePrecision = (typeof occurrencePrecisions)[number];
export type Occurrence = {
  occurredAt: string | null;
  occurredEnd: string | null;
  occurredLabel: string | null;
  occurredTimezone: string;
  datePrecision: OccurrencePrecision;
};
export type OccurrenceDraft = {
  precision: OccurrencePrecision;
  start: string;
  end: string;
  label: string;
  timezone: string;
};
export const occurrencePrecisionLabels: Record<OccurrencePrecision, string> = {
  exact: "Exact date & time",
  day: "Day",
  month: "Month",
  year: "Year",
  approximate: "Approximate",
  age: "Age",
  range: "Date range",
  unknown: "Unknown",
};
export function validTimezone(value: unknown): value is string {
  if (
    typeof value !== "string" ||
    !/^[A-Za-z][A-Za-z0-9_+./-]*$/.test(value) ||
    value.length > 100
  )
    return false;
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: value }).format();
    return true;
  } catch {
    return false;
  }
}
export function validateOccurrence(
  value: Occurrence,
  span = false,
): string | null {
  if (!occurrencePrecisions.includes(value.datePrecision))
    return "Choose a supported date precision.";
  if (!validTimezone(value.occurredTimezone))
    return "Choose a valid IANA time zone, for example America/Los_Angeles.";
  if (
    value.occurredLabel !== null &&
    (typeof value.occurredLabel !== "string" ||
      value.occurredLabel.length > 200)
  )
    return "Keep the date description under 200 characters.";
  for (const date of [value.occurredAt, value.occurredEnd])
    if (
      date !== null &&
      (typeof date !== "string" ||
        !/^\d{4}-\d{2}-\d{2}T/.test(date) ||
        date.startsWith("0000-") ||
        !Number.isFinite(Date.parse(date)) ||
        new Date(`${date.slice(0, 10)}T12:00:00Z`)
          .toISOString()
          .slice(0, 10) !== date.slice(0, 10))
    )
      return "Choose a valid date.";
  if (
    ["exact", "day", "month", "year", "range"].includes(value.datePrecision) &&
    !value.occurredAt
  )
    return "Add the known date, or choose Unknown.";
  if (
    value.datePrecision === "unknown" &&
    (value.occurredAt || value.occurredEnd)
  )
    return "Unknown dates cannot have calendar dates.";
  if (
    ["age", "approximate"].includes(value.datePrecision) &&
    !value.occurredLabel?.trim()
  )
    return "Describe the age or approximate period you remember.";
  if (
    value.occurredEnd &&
    (!value.occurredAt ||
      Date.parse(value.occurredEnd) < Date.parse(value.occurredAt))
  )
    return "The end date must be on or after the start date.";
  if (
    value.occurredEnd &&
    !span &&
    !["range", "approximate", "age"].includes(value.datePrecision)
  )
    return "Only ranges, ages, or approximate periods can have an end date.";
  return null;
}

function wallTime(iso: string, timezone: string) {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23",
  }).formatToParts(new Date(iso));
  const get = (type: string) => parts.find((p) => p.type === type)?.value ?? "";
  return `${get("year").padStart(4, "0")}-${get("month")}-${get("day")}T${get("hour")}:${get("minute")}:${get("second")}`;
}

// Resolve wall-clock input in the recorded zone, including fractional offsets and
// DST changes. Reject nonexistent times instead of silently rolling them forward.
export function wallTimeToISO(local: string, timezone: string): string | null {
  if (
    !validTimezone(timezone) ||
    local.startsWith("0000-") ||
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?$/.test(local)
  )
    return null;
  const target = local.length === 16 ? `${local}:00` : local;
  const targetMS = Date.parse(`${target}Z`);
  if (
    !Number.isFinite(targetMS) ||
    new Date(targetMS).toISOString().slice(0, 19) !== target
  )
    return null;
  const candidates = new Set<number>();
  for (const hours of [-24, -12, 0, 12, 24]) {
    const sample = targetMS + hours * 3_600_000;
    const offset =
      Date.parse(`${wallTime(new Date(sample).toISOString(), timezone)}Z`) -
      sample;
    const candidate = targetMS - offset;
    if (wallTime(new Date(candidate).toISOString(), timezone) === target)
      candidates.add(candidate);
  }
  // During the repeated fall-back hour, a new edit uses the earlier instant.
  // Unchanged fields preserve their original instant through resolveOccurrenceDraft.
  return candidates.size
    ? new Date(Math.min(...candidates)).toISOString()
    : null;
}

export function occurrenceDraft(value: Occurrence): OccurrenceDraft {
  const local = (date: string | null) => {
    if (!date) return "";
    const full = wallTime(date, value.occurredTimezone);
    return value.datePrecision === "exact"
      ? full
      : full.slice(
          0,
          value.datePrecision === "year"
            ? 4
            : value.datePrecision === "month"
              ? 7
              : 10,
        );
  };
  return {
    precision: value.datePrecision,
    start: local(value.occurredAt),
    end: local(value.occurredEnd),
    label: value.occurredLabel ?? "",
    timezone: value.occurredTimezone,
  };
}

export function resolveOccurrenceDraft(
  draft: OccurrenceDraft,
  original?: Occurrence,
  span = false,
): { value: Occurrence; error?: never } | { error: string; value?: never } {
  if (!validTimezone(draft.timezone))
    return {
      error: "Choose a valid IANA time zone, for example America/Los_Angeles.",
    };
  const previous = original ? occurrenceDraft(original) : null;
  const convert = (text: string, key: "start" | "end") => {
    if (!text) return null;
    if (
      previous &&
      previous.precision === draft.precision &&
      previous.timezone === draft.timezone &&
      previous[key] === text
    )
      return key === "start" ? original!.occurredAt : original!.occurredEnd;
    const local =
      draft.precision === "exact"
        ? text
        : `${text}${draft.precision === "year" ? "-01-01" : draft.precision === "month" ? "-01" : ""}T12:00:00`;
    return wallTimeToISO(local, draft.timezone);
  };
  const start =
    draft.precision === "unknown" ? null : convert(draft.start, "start");
  const bounded =
    draft.precision !== "unknown" &&
    (span || ["range", "approximate", "age"].includes(draft.precision));
  const end = bounded ? convert(draft.end, "end") : null;
  if (
    (draft.start && !start && draft.precision !== "unknown") ||
    (draft.end && !end && bounded)
  )
    return {
      error:
        "Choose a valid calendar date and time. This time may not exist during a daylight-saving change.",
    };
  const value: Occurrence = {
    datePrecision: draft.precision,
    occurredAt: start,
    occurredEnd: end,
    occurredLabel: draft.label.trim() || null,
    occurredTimezone: draft.timezone,
  };
  const error = validateOccurrence(value, span);
  return error ? { error } : { value };
}

export function occurrenceLabel(value: Occurrence): string {
  if (value.occurredLabel) return value.occurredLabel;
  if (value.datePrecision === "unknown" || !value.occurredAt)
    return "Date unknown";
  const format = (date: string) =>
    new Intl.DateTimeFormat("en-US", {
      timeZone: value.occurredTimezone,
      year: "numeric",
      ...(value.datePrecision !== "year" ? { month: "short" as const } : {}),
      ...(!["year", "month"].includes(value.datePrecision)
        ? { day: "numeric" as const }
        : {}),
      ...(value.datePrecision === "exact"
        ? { hour: "numeric" as const, minute: "2-digit" as const }
        : {}),
    }).format(new Date(date));
  return `${format(value.occurredAt)}${value.occurredEnd ? ` to ${format(value.occurredEnd)}` : value.datePrecision === "range" ? " onward" : ""}`;
}

export function occurrenceSpanLabel(value: Occurrence): string {
  value = {
    ...value,
    occurredTimezone: validTimezone(value.occurredTimezone)
      ? value.occurredTimezone
      : "UTC",
  };
  if (value.occurredLabel) return value.occurredLabel;
  if (!value.occurredAt || value.datePrecision === "unknown")
    return "Date unknown";
  const point = {
    ...value,
    occurredEnd: null,
    datePrecision:
      value.datePrecision === "range" ? ("day" as const) : value.datePrecision,
  };
  const start = occurrenceLabel(point);
  return value.occurredEnd
    ? `${start} - ${occurrenceLabel({ ...point, occurredAt: value.occurredEnd })}`
    : `Since ${start}`;
}

export function occurrenceDurationLabel(
  value: Occurrence,
  now = new Date(),
): string {
  if (!value.occurredAt || value.datePrecision === "unknown")
    return "Duration unavailable";
  const parts = (date: string) =>
    Object.fromEntries(
      new Intl.DateTimeFormat("en-CA", {
        timeZone: validTimezone(value.occurredTimezone)
          ? value.occurredTimezone
          : "UTC",
        year: "numeric",
        month: "numeric",
        day: "numeric",
      })
        .formatToParts(new Date(date))
        .filter((part) => part.type !== "literal")
        .map((part) => [part.type, Number(part.value)]),
    );
  try {
    const start = parts(value.occurredAt),
      end = parts(value.occurredEnd ?? now.toISOString());
    if (value.datePrecision === "year") {
      const years = Math.max(0, end.year - start.year);
      return years
        ? `About ${years} ${years === 1 ? "year" : "years"}`
        : "Less than a year (approx.)";
    }
    let months = (end.year - start.year) * 12 + end.month - start.month;
    if (value.datePrecision !== "month" && end.day < start.day) months -= 1;
    months = Math.max(0, months);
    const approximate = ["month", "age", "approximate"].includes(
      value.datePrecision,
    );
    if (!months)
      return approximate ? "Less than a month (approx.)" : "Less than a month";
    const years = Math.floor(months / 12),
      remainder = months % 12;
    const label = [
      years ? `${years} ${years === 1 ? "year" : "years"}` : "",
      remainder ? `${remainder} ${remainder === 1 ? "month" : "months"}` : "",
    ]
      .filter(Boolean)
      .join(" ");
    return approximate ? `About ${label}` : label;
  } catch {
    return "Duration unavailable";
  }
}
