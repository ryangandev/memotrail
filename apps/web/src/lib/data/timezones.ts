export const commonTimezones = [
  "UTC",
  "America/Los_Angeles",
  "America/Vancouver",
  "America/Denver",
  "America/Chicago",
  "America/New_York",
  "America/Toronto",
  "America/Sao_Paulo",
  "Europe/London",
  "Europe/Paris",
  "Europe/Berlin",
  "Africa/Johannesburg",
  "Asia/Dubai",
  "Asia/Kolkata",
  "Asia/Kathmandu",
  "Asia/Singapore",
  "Asia/Shanghai",
  "Asia/Hong_Kong",
  "Asia/Tokyo",
  "Asia/Seoul",
  "Australia/Sydney",
  "Pacific/Auckland",
] as const;

let cachedSupportedTimezones: readonly string[] | null = null;

export function supportedTimezones() {
  if (cachedSupportedTimezones) return cachedSupportedTimezones;

  let supported: string[] = [];
  try {
    supported = Intl.supportedValuesOf("timeZone");
  } catch {
    // Older browsers still receive the curated list above.
  }

  cachedSupportedTimezones = [...new Set([...commonTimezones, ...supported])];
  return cachedSupportedTimezones;
}

export function timezoneLabel(timezone: string) {
  if (timezone === "UTC") return "UTC";

  const [region, ...locationParts] = timezone.split("/");
  const location = locationParts.join(" / ").replaceAll("_", " ");
  return location ? `${location} - ${region}` : timezone.replaceAll("_", " ");
}

export function timezoneOffsetLabel(
  timezone: string,
  referenceDate: string | Date = new Date(),
) {
  const reference = offsetReferenceDate(referenceDate);
  const cacheKey = `${timezone}:${reference.toISOString().slice(0, 10)}`;
  if (offsetLabelCache.has(cacheKey)) return offsetLabelCache.get(cacheKey)!;

  let offset = "";
  try {
    const zoneName = new Intl.DateTimeFormat("en-US", {
      hour: "2-digit",
      timeZone: timezone,
      timeZoneName: "longOffset",
    })
      .formatToParts(reference)
      .find((part) => part.type === "timeZoneName")?.value;
    const match = zoneName?.match(/^GMT(?:([+-])(\d{1,2}):(\d{2}))?$/);
    if (match) {
      offset = match[1]
        ? `UTC${match[1]}${match[2].padStart(2, "0")}:${match[3]}`
        : "UTC+00:00";
    }
  } catch {
    // Preserve the IANA label if this runtime cannot format its offset.
  }

  offsetLabelCache.set(cacheKey, offset);
  return offset;
}

export function timezoneOptionLabel(
  timezone: string,
  referenceDate?: string | Date,
) {
  const offset = timezoneOffsetLabel(timezone, referenceDate);
  return `${offset ? `(${offset}) ` : ""}${timezoneLabel(timezone)}`;
}

function offsetReferenceDate(value: string | Date) {
  if (value instanceof Date && Number.isFinite(value.getTime())) return value;
  if (typeof value === "string") {
    const day = value.match(/^\d{4}-\d{2}-\d{2}/)?.[0];
    if (day) {
      const reference = new Date(`${day}T12:00:00Z`);
      if (Number.isFinite(reference.getTime())) return reference;
    }
  }
  return new Date();
}

const offsetLabelCache = new Map<string, string>();
