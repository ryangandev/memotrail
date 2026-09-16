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

export type WikiItemSearchGroup = {
  label: string;
  options: readonly {
    label: string;
    value: string;
  }[];
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

export const wikiItemSearchGroups: readonly WikiItemSearchGroup[] = [
  {
    label: "Kinds",
    options: [
      { label: "Captures", value: "capture" },
      { label: "Writing", value: "writing" },
      { label: "Entities", value: "entity" },
      { label: "Events", value: "event" },
      { label: "Stories", value: "story" },
      { label: "Goals", value: "goal" },
    ],
  },
  {
    label: "Writing types",
    options: [
      { label: "Notes", value: "note" },
      { label: "Journals", value: "journal" },
      { label: "Reflections", value: "reflection" },
      { label: "Lessons", value: "lesson" },
      { label: "Ideas", value: "idea" },
    ],
  },
  {
    label: "Entity types",
    options: [
      { label: "People", value: "person" },
      { label: "Places", value: "place" },
      { label: "Homes", value: "home" },
      { label: "Vehicles", value: "vehicle" },
    ],
  },
  {
    label: "Event types",
    options: [
      { label: "Memories", value: "memory" },
      { label: "First Times", value: "first_time" },
      { label: "Milestones", value: "milestone" },
      { label: "Trips", value: "trip" },
      { label: "Life Stages", value: "life_stage" },
    ],
  },
  {
    label: "Story types",
    options: [{ label: "Chapters", value: "chapter" }],
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

export function wikiItemIdentityLabel(kind: WikiItemKind, subtype: string) {
  const kindLabel = wikiItemKindLabel(kind);
  const subtypeLabel = wikiItemSubtypeLabel(kind, subtype);
  if (
    kind === "capture" ||
    kind === "goal" ||
    kindLabel.toLocaleLowerCase() === subtypeLabel.toLocaleLowerCase()
  ) {
    return kindLabel;
  }
  return `${kindLabel} · ${subtypeLabel}`;
}

export function wikiItemIdentityFromLegacy(
  entryType: string,
  inboxStatus: "organized" | "unreviewed",
): { itemKind: WikiItemKind; itemSubtype: string } {
  switch (entryType) {
    case "first_time":
      return { itemKind: "event", itemSubtype: "first_time" };
    case "life_stage":
      return { itemKind: "event", itemSubtype: "life_stage" };
    case "home":
      return { itemKind: "entity", itemSubtype: "home" };
    case "vehicle":
      return { itemKind: "entity", itemSubtype: "vehicle" };
    case "goal":
      return { itemKind: "goal", itemSubtype: "goal" };
    default:
      return inboxStatus === "unreviewed"
        ? { itemKind: "capture", itemSubtype: "quick_capture" }
        : { itemKind: "writing", itemSubtype: "note" };
  }
}

export function wikiEntryHref(item: {
  id: string;
  inboxStatus: "organized" | "unreviewed";
  itemKind: WikiItemKind;
  itemSubtype: string;
  recordId?: string;
  recordSource?: "entry" | "person" | "place";
}) {
  if (
    item.itemKind === "entity" &&
    item.itemSubtype === "person" &&
    item.recordSource === "person" &&
    item.recordId
  ) {
    return `/people?person=${item.recordId}`;
  }
  if (
    item.itemKind === "entity" &&
    item.itemSubtype === "place" &&
    item.recordSource === "place" &&
    item.recordId
  ) {
    return `/places?place=${item.recordId}`;
  }
  if (item.itemKind === "entity" && item.itemSubtype === "home") {
    return `/homes?entry=${item.id}`;
  }
  if (item.itemKind === "entity" && item.itemSubtype === "vehicle") {
    return `/vehicles?entry=${item.id}`;
  }
  if (item.itemKind === "goal") {
    return `/goals?entry=${item.id}`;
  }
  if (item.itemKind === "capture" && item.inboxStatus === "unreviewed") {
    return "/inbox";
  }
  return `/history?entry=${item.id}`;
}
