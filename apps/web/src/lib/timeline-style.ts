export const TIMELINE_STYLE_COOKIE_NAME = "memotrail-timeline-style";

export const timelineStyles = ["classic", "vertical", "sticky-year"] as const;

export type TimelineStyle = (typeof timelineStyles)[number];

export function parseTimelineStyle(value: unknown): TimelineStyle | null {
  return timelineStyles.includes(value as TimelineStyle)
    ? (value as TimelineStyle)
    : null;
}

export function storedTimelineStyle(
  value: string | undefined,
  ownerId: string,
): TimelineStyle {
  const prefix = `${ownerId}:`;
  return value?.startsWith(prefix)
    ? (parseTimelineStyle(value.slice(prefix.length)) ?? "classic")
    : "classic";
}

export function timelineStyleCookieValue(
  ownerId: string,
  style: TimelineStyle,
) {
  return `${ownerId}:${style}`;
}
