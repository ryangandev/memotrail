export const timelineIdeaLinks = [
  {
    href: "/timeline/ideas/vertical-spine",
    label: "01 Vertical Spine",
    shortLabel: "Spine",
  },
  {
    href: "/timeline/ideas/swimlane",
    label: "03 Swimlane",
    shortLabel: "Swimlane",
  },
] as const;

export function timelineIdeaReturnPath(value: string | string[] | undefined) {
  return typeof value === "string" &&
    timelineIdeaLinks.some((idea) => idea.href === value)
    ? value
    : null;
}
