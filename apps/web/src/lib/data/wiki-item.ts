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
      { label: "Goals", value: "goal" },
    ],
  },
  {
    label: "Focused records",
    options: [
      { label: "First Times", value: "first_time" },
      { label: "People", value: "person" },
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
      return "Goal";
  }
}

export function wikiItemSubtypeLabel(kind: WikiItemKind, subtype: string) {
  if (kind === "entry") {
    if (subtype === "first_time") return "First Time";
    if (subtype === "moment") return "Moment";
    if (subtype === "period") return "Period";
    return "Entry";
  }
  if (kind === "entity" && subtype === "home") return "Home";
  if (kind === "entity" && subtype === "vehicle") return "Vehicle";
  if (kind === "goal")
    return subtype === "bucket_list" ? "Bucket List" : "Goal";
  return subtype
    .split("_")
    .map((part) => part.charAt(0).toLocaleUpperCase() + part.slice(1))
    .join(" ");
}

export function wikiItemIdentityLabel(kind: WikiItemKind, subtype: string) {
  const kindLabel = wikiItemKindLabel(kind);
  const subtypeLabel = wikiItemSubtypeLabel(kind, subtype);
  return kindLabel.toLocaleLowerCase() === subtypeLabel.toLocaleLowerCase()
    ? kindLabel
    : subtypeLabel;
}

export function wikiEntryHref(item: {
  id: string;
  inboxStatus: "organized" | "unreviewed";
  itemKind: WikiItemKind;
  itemSubtype: string;
  recordId?: string;
  recordSource?: "entry" | "person" | "place";
}) {
  if (item.inboxStatus === "unreviewed") {
    return `/inbox?entry=${item.id}`;
  }
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
  if (item.itemKind === "entry" && item.itemSubtype === "first_time") {
    return `/first-times?entry=${item.id}`;
  }
  if (
    item.itemKind === "entry" &&
    (item.itemSubtype === "moment" || item.itemSubtype === "period")
  ) {
    return `/timeline?entry=${item.id}`;
  }
  return `/items/${item.id}`;
}
