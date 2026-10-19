import type { ImportSource } from "./types";

/** What the import page tells a person about one kind of export. */
export type ImportSourceGuide = {
  source: ImportSource;
  name: string;
  summary: string;
  steps: string[];
  notes: string[];
};

/**
 * The sources in the order they are offered. Each guide is the plain-language way to get a ZIP
 * out of the app, written to be kept honest: where an app's export changes, change it here.
 */
export const importSourceGuides: ImportSourceGuide[] = [
  {
    name: "Markdown folder",
    notes: [
      "Obsidian, iA Writer, and most note apps that save plain files work this way.",
      "Dates are read from frontmatter (date or created) and from the note title when it is only a date.",
    ],
    source: "markdown",
    steps: [
      "Put the notes and their pictures together in one folder.",
      "Compress the folder into a ZIP.",
      "Choose the ZIP below.",
    ],
    summary: "Notes saved as Markdown files, with their pictures beside them.",
  },
  {
    name: "Apple Journal",
    notes: [
      "Export with your device language set to English, so the dates can be read.",
      "A large journal can take several minutes to export while photos finish downloading from iCloud.",
    ],
    source: "apple_journal",
    steps: [
      "On iPhone, open Journal, choose All Entries, tap More, then Export, and save to iCloud Drive. On a Mac, choose File, Export, then Export.",
      "In Files (or Finder), press and hold the exported folder and choose Compress.",
      "Choose the ZIP below.",
    ],
    summary: "Entries, photos, and dates from the Journal app.",
  },
  {
    name: "Apple Notes",
    notes: [
      "Use a Mac. On iPhone, Apple exports one note at a time.",
      "Apple's own Markdown export may not include dates, so those notes arrive undated. Exporter apps for Apple Notes that keep creation dates in each file give notes their real dates.",
    ],
    source: "apple_notes",
    steps: [
      "In Notes on a Mac, select the notes or the folder to export.",
      "Choose File, Export As, then Markdown.",
      "Keep the notes and the Attachments folder together, compress the folder, and choose the ZIP below.",
    ],
    summary: "Notes exported as Markdown from Notes on a Mac.",
  },
  {
    name: "Notion",
    notes: [
      "A large export is emailed to you and the link expires after 7 days.",
      "Pages carry no date in the export. Database rows with a date property are dated from it.",
    ],
    source: "notion",
    steps: [
      "In Notion, open the page or database menu and choose Export.",
      "Choose Markdown & CSV, and turn on Include subpages and Create folders for subpages.",
      "Choose the ZIP exactly as Notion made it. You do not need to unzip it.",
    ],
    summary: "Pages and database rows exported as Markdown and CSV.",
  },
  {
    name: "Day One",
    notes: ["Every entry keeps its exact time, time zone, tags, and place."],
    source: "day_one",
    steps: [
      "In Day One, choose File, Export, then JSON.",
      "Choose the ZIP below.",
    ],
    summary: "A Day One journal exported as JSON, with its photos.",
  },
];

export function sourceGuide(source: ImportSource) {
  return importSourceGuides.find((guide) => guide.source === source);
}

/** Whether what was detected agrees with the source the person chose. */
export function detectionAgrees(
  chosen: ImportSource,
  detected: { source: ImportSource; confidence: number } | null | undefined,
) {
  if (!detected || detected.confidence < 0.7) return true;
  if (chosen === "apple_notes") return detected.source === "markdown";
  return detected.source === chosen;
}

/** A size in the units people read, such as 50 MB or 1.5 GB. */
export function formatBytes(bytes: number) {
  if (bytes >= 1024 ** 3) return `${(bytes / 1024 ** 3).toFixed(1)} GB`;
  if (bytes >= 1024 ** 2) return `${Math.round(bytes / 1024 ** 2)} MB`;
  return `${Math.max(1, Math.round(bytes / 1024))} KB`;
}
