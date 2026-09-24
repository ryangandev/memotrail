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
  {
    href: "/timeline/ideas/sticky-year",
    label: "07 Sticky Year",
    shortLabel: "Sticky Year",
  },
  {
    href: "/timeline/ideas/chapters",
    label: "08 Chapters",
    shortLabel: "Chapters",
  },
  {
    href: "/timeline/ideas/minimal-index",
    label: "18 Minimal Index",
    shortLabel: "Minimal",
  },
] as const;

export function timelineIdeaReturnPath(value: string | string[] | undefined) {
  return typeof value === "string" &&
    timelineIdeaLinks.some((idea) => idea.href === value)
    ? value
    : null;
}
