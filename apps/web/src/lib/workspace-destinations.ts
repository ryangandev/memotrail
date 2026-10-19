import type { IconName } from "@/generated/design-system";

/** A place in the workspace navigation. */
export type WorkspaceDestination =
  | "home"
  | "timeline"
  | "library"
  | "first-times"
  | "reviews"
  | "tags"
  | "import"
  | "trash"
  | "settings";

export type DestinationLink = {
  destination: WorkspaceDestination;
  href: string;
  icon: IconName;
  label: string;
};

export const destinationLinks = {
  home: {
    destination: "home",
    href: "/",
    icon: "dashboard",
    label: "Dashboard",
  },
  timeline: {
    destination: "timeline",
    href: "/timeline",
    icon: "timeline",
    label: "Timeline",
  },
  library: {
    destination: "library",
    href: "/library",
    icon: "archive",
    label: "Library",
  },
  "first-times": {
    destination: "first-times",
    href: "/first-times",
    icon: "star",
    label: "First Times",
  },
  reviews: {
    destination: "reviews",
    href: "/reviews",
    icon: "quote",
    label: "Reviews",
  },
  tags: { destination: "tags", href: "/tags", icon: "tag", label: "Tags" },
  import: {
    destination: "import",
    href: "/settings/import",
    icon: "inbox",
    label: "Import",
  },
  trash: {
    destination: "trash",
    href: "/trash",
    icon: "trash",
    label: "Trash",
  },
  settings: {
    destination: "settings",
    href: "/settings",
    icon: "settings",
    label: "Settings",
  },
} as const satisfies Record<WorkspaceDestination, DestinationLink>;

/** The sidebar's three groups, in order: the daily places, the focused views, and the tools pinned at its foot. */
export const sidebarGroups: readonly (readonly DestinationLink[])[] = [
  [destinationLinks.home, destinationLinks.timeline, destinationLinks.library],
  [
    destinationLinks["first-times"],
    destinationLinks.reviews,
    destinationLinks.tags,
  ],
  [destinationLinks.import, destinationLinks.trash, destinationLinks.settings],
];

/** The phone tab bar; everything else is in More. */
export const tabBarDestinations: readonly DestinationLink[] = [
  destinationLinks.home,
  destinationLinks.timeline,
  destinationLinks.library,
];

/** The phone More list, in sidebar order. */
export const moreDestinations: readonly DestinationLink[] = [
  destinationLinks["first-times"],
  destinationLinks.reviews,
  destinationLinks.tags,
  destinationLinks.import,
  destinationLinks.trash,
  destinationLinks.settings,
];

/**
 * The destination a path belongs to. An Item page names its own destination from what the Item
 * is, so its path alone belongs to none, and neither does an address that does not exist.
 */
export function destinationForPathname(
  pathname: string,
): WorkspaceDestination | null {
  if (pathname === "/") return "home";
  const within = (prefix: string) =>
    pathname === prefix || pathname.startsWith(`${prefix}/`);
  if (within("/timeline")) return "timeline";
  if (within("/library")) return "library";
  if (within("/first-times")) return "first-times";
  if (within("/reviews")) return "reviews";
  if (within("/tags")) return "tags";
  if (within("/trash")) return "trash";
  if (within("/settings/import")) return "import";
  if (within("/settings")) return "settings";
  return null;
}

/**
 * Where an Item belongs: an Item in Trash to Trash, a Chapter to Timeline, a First Time to
 * First Times, and every other Entry to Library. Its back link and the active navigation follow it.
 */
export function destinationForEntry(entry: {
  deleted_at: string | null;
  is_first_time: boolean;
  item_subtype: string;
}): WorkspaceDestination {
  if (entry.deleted_at) return "trash";
  if (entry.item_subtype === "chapter") return "timeline";
  if (entry.is_first_time) return "first-times";
  return "library";
}
