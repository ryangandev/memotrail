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
