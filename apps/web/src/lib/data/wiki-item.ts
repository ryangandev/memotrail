import { milestoneLabel, type Milestone } from "./milestone";

export const wikiItemKinds = ["entry", "entity", "goal"] as const;

export type WikiItemKind = (typeof wikiItemKinds)[number];

export type WikiItemSearchGroup = {
  label: string;
  options: readonly {
    label: string;
    value: string;
  }[];
};

export const wikiItemSearchGroups: readonly WikiItemSearchGroup[] = [
  {
    label: "Records",
    options: [
      { label: "Entries", value: "entry" },
      { label: "Entities", value: "entity" },
      { label: "Someday", value: "goal" },
    ],
  },
  {
    label: "Focused records",
    options: [
      { label: "Timeline milestones", value: "milestone" },
      { label: "First Times", value: "first_time" },
      { label: "Homes", value: "home" },
      { label: "Vehicles", value: "vehicle" },
    ],
  },
] as const;

export function isWikiItemKind(value: unknown): value is WikiItemKind {
  return (
    typeof value === "string" && wikiItemKinds.includes(value as WikiItemKind)
  );
}

export function wikiItemKindLabel(kind: WikiItemKind) {
  switch (kind) {
    case "entry":
      return "Entry";
    case "entity":
      return "Entity";
    case "goal":
      return "Someday";
  }
}

export function wikiItemSubtypeLabel(kind: WikiItemKind, subtype: string) {
  if (kind === "entry") return "Entry";
  if (kind === "entity" && subtype === "home") return "Home";
  if (kind === "entity" && subtype === "vehicle") return "Vehicle";
  if (kind === "goal") return "Someday";
  return subtype
    .split("_")
    .map((part) => part.charAt(0).toLocaleUpperCase() + part.slice(1))
    .join(" ");
}

// A milestone Entry reads as what it is on Timeline: a First Time, a Period, or a Moment.
export function wikiItemIdentityLabel(
  kind: WikiItemKind,
  subtype: string,
  milestone: Pick<Milestone, "isFirstTime" | "shape"> | null = null,
) {
  if (kind === "entry" && milestone) return milestoneLabel(milestone);
  const kindLabel = wikiItemKindLabel(kind);
  const subtypeLabel = wikiItemSubtypeLabel(kind, subtype);
  return kindLabel.toLocaleLowerCase() === subtypeLabel.toLocaleLowerCase()
    ? kindLabel
    : subtypeLabel;
}

export function wikiEntryHref(item: {
  id: string;
  itemKind: WikiItemKind;
  itemSubtype: string;
}) {
  if (item.itemKind === "entity" && item.itemSubtype === "home") {
    return `/homes/${item.id}`;
  }
  if (item.itemKind === "entity" && item.itemSubtype === "vehicle") {
    return `/vehicles/${item.id}`;
  }
  if (item.itemKind === "goal") {
    return `/goals/${item.id}`;
  }
  return `/items/${item.id}`;
}
