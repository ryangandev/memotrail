export const wikiItemKinds = [
  "capture",
  "writing",
  "entity",
  "event",
  "story",
  "goal",
] as const;

export type WikiItemKind = (typeof wikiItemKinds)[number];
export type ReviewableWikiItemKind = "event" | "story" | "writing";

export type WikiItemPreset = {
  description: string;
  kind: ReviewableWikiItemKind;
  label: string;
  subtype: string;
};

export const reviewableWikiItemPresets: readonly WikiItemPreset[] = [
  {
    description: "A flexible thought that can stay simple.",
    kind: "writing",
    label: "Note",
    subtype: "note",
  },
  {
    description: "A dated account of your day or life.",
    kind: "writing",
    label: "Journal",
    subtype: "journal",
  },
  {
    description: "Meaning you made from an experience.",
    kind: "writing",
    label: "Reflection",
    subtype: "reflection",
  },
  {
    description: "Something you want to remember learning.",
    kind: "writing",
    label: "Lesson",
    subtype: "lesson",
  },
  {
    description: "A possibility worth returning to.",
    kind: "writing",
    label: "Idea",
    subtype: "idea",
  },
  {
    description: "Something that happened and matters to you.",
    kind: "event",
    label: "Memory",
    subtype: "memory",
  },
  {
    description: "The first time something happened.",
    kind: "event",
    label: "First Time",
    subtype: "first_time",
  },
  {
    description: "A meaningful marker in your life.",
    kind: "event",
    label: "Milestone",
    subtype: "milestone",
  },
  {
    description: "A journey or visit with a beginning and end.",
    kind: "event",
    label: "Trip",
    subtype: "trip",
  },
  {
    description: "A deliberately authored life story.",
    kind: "story",
    label: "Chapter",
    subtype: "chapter",
  },
] as const;

export function isWikiItemKind(value: unknown): value is WikiItemKind {
  return (
    typeof value === "string" && wikiItemKinds.includes(value as WikiItemKind)
  );
}

export function isReviewableWikiItemKind(
  value: unknown,
): value is ReviewableWikiItemKind {
  return value === "writing" || value === "event" || value === "story";
}

export function validReviewableWikiItemPreset(
  kind: unknown,
  subtype: unknown,
): kind is ReviewableWikiItemKind {
  return reviewableWikiItemPresets.some(
    (preset) => preset.kind === kind && preset.subtype === subtype,
  );
}

export function reviewablePresetsForKind(kind: ReviewableWikiItemKind) {
  return reviewableWikiItemPresets.filter((preset) => preset.kind === kind);
}

export function initialReviewClassification(value: {
  itemKind: WikiItemKind;
  itemSubtype: string;
}) {
  if (
    isReviewableWikiItemKind(value.itemKind) &&
    validReviewableWikiItemPreset(value.itemKind, value.itemSubtype)
  ) {
    return { itemKind: value.itemKind, itemSubtype: value.itemSubtype };
  }

  return { itemKind: "writing" as const, itemSubtype: "note" };
}

export function wikiItemKindLabel(kind: WikiItemKind) {
  switch (kind) {
    case "capture":
      return "Capture";
    case "writing":
      return "Writing";
    case "entity":
      return "Entity";
    case "event":
      return "Event";
    case "story":
      return "Story";
    case "goal":
      return "Goal";
  }
}

export function wikiItemSubtypeLabel(kind: WikiItemKind, subtype: string) {
  const preset = reviewableWikiItemPresets.find(
    (candidate) => candidate.kind === kind && candidate.subtype === subtype,
  );
  if (preset) return preset.label;
  if (kind === "entity" && subtype === "home") return "Home";
  if (kind === "entity" && subtype === "vehicle") return "Vehicle";
  if (kind === "goal")
    return subtype === "bucket_list" ? "Bucket List" : "Goal";
  if (kind === "capture") return "Unorganized";
  return subtype
    .split("_")
    .map((part) => part.charAt(0).toLocaleUpperCase() + part.slice(1))
    .join(" ");
}
