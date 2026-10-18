import { validTimezone } from "./occurrence";

/**
 * A Trash date in the person's profile time zone. The locale and zone are
 * explicit, so the server and the browser print the same text.
 */
export function trashDate(value: string, timezone: string) {
  return new Intl.DateTimeFormat("en-US", {
    day: "numeric",
    month: "short",
    timeZone: validTimezone(timezone) ? timezone : "UTC",
    year: "numeric",
  }).format(new Date(value));
}

/**
 * How long an item stays recoverable, counted from when the page was
 * rendered rather than from the reader's clock, so hydration agrees.
 */
export function trashRetention(expiresAt: string, renderedAt: string) {
  const days = Math.ceil(
    (new Date(expiresAt).getTime() - new Date(renderedAt).getTime()) /
      86_400_000,
  );

  if (days <= 0) {
    return "Eligible for cleanup since";
  }

  return `${days} ${days === 1 ? "day" : "days"} to restore · through`;
}
