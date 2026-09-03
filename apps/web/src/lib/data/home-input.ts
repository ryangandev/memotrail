export const homeTimezoneCookieName = "memotrail_timezone";

export function normalizeHomeTimezone(value: unknown) {
  if (typeof value !== "string") {
    return "UTC";
  }

  const timezone = value.trim();

  if (!timezone || timezone.length > 100) {
    return "UTC";
  }

  try {
    new Intl.DateTimeFormat("en-US", { timeZone: timezone }).format(
      new Date(0),
    );
    return timezone;
  } catch {
    return "UTC";
  }
}

export function localDateInTimezone(date: Date, timezone: string): string {
  const parts = new Intl.DateTimeFormat("en-US", {
    day: "2-digit",
    month: "2-digit",
    timeZone: normalizeHomeTimezone(timezone),
    year: "numeric",
  }).formatToParts(date);
  const values = new Map(parts.map((part) => [part.type, part.value]));

  return `${values.get("year")}-${values.get("month")}-${values.get("day")}`;
}

export function greetingInTimezone(date: Date, timezone: string) {
  const hour = Number(
    new Intl.DateTimeFormat("en-US", {
      hour: "numeric",
      hourCycle: "h23",
      timeZone: normalizeHomeTimezone(timezone),
    })
      .formatToParts(date)
      .find((part) => part.type === "hour")?.value ?? "12",
  );

  if (hour < 12) {
    return "Good morning";
  }

  if (hour < 18) {
    return "Good afternoon";
  }

  return "Good evening";
}
