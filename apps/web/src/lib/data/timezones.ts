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
