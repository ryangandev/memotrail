/**
 * What a person agrees to before Claude reads their writing. The version is stored with the
 * time they accepted it, and every change to a sentence below bumps it so people are asked again.
 * The sources were checked on October 18, 2026.
 */
export const REVIEW_DISCLOSURE_VERSION = "2026-10-18";

export const REVIEW_DISCLOSURE_TITLE = "Before Claude reads your Entries";

export const REVIEW_DISCLOSURE_INTRO = [
  "Reviews and Chapter suggestions are written by Claude, an AI model made by Anthropic.",
  "To write one, MemoTrail sends part of your writing to Anthropic.",
  "Nothing is sent until you choose Make a review, or while Suggest Chapters is on.",
] as const;

export const REVIEW_DISCLOSURE_SECTIONS = [
  {
    heading: "What is sent",
    points: [
      "For a Chapter review: the Chapter's name, dates, and writing, and the title, date, tags, and writing of every Entry dated inside it.",
      "For a year review: the title, date, tags, and writing of every Entry dated in that year, and the names and dates of your Chapters during it.",
      "For Chapter suggestions, about once a month: the title, date, tags, and first 500 characters of your Entries from the last 18 months, and the names and dates of your Chapters.",
      "Text only. Photos, Locations, your name, and your email address are never sent.",
      "When a period holds more writing than one review reads, MemoTrail sends part of it and the review says how much it read.",
    ],
  },
  {
    heading: "What Anthropic does with it",
    points: [
      "Anthropic does not use it to train its models. Its commercial terms do not allow training on this content, and MemoTrail does not share it for training or send feedback about it.",
      "Anthropic deletes it automatically within 30 days.",
      "If Anthropic's automated safety systems flag a request, Anthropic may keep it for up to 2 years, and it may keep it longer when the law requires.",
      "MemoTrail has no zero data retention agreement with Anthropic, so this is not a promise that nothing is stored.",
    ],
  },
  {
    heading: "What MemoTrail keeps",
    points: [
      "MemoTrail saves each review so you can read it again, and includes it in your export.",
      "Reviews never change your Entries.",
      "Deleting an Entry forever also deletes every review that read it.",
      "Turning reviews off deletes every saved review.",
    ],
  },
] as const;

export const REVIEW_DISCLOSURE_SOURCES = [
  {
    label: "How long do you store my organization's data?",
    href: "https://privacy.claude.com/en/articles/7996866-how-long-do-you-store-my-organization-s-data",
  },
  {
    label: "Is my data used for model training?",
    href: "https://privacy.claude.com/en/articles/7996868-is-my-data-used-for-model-training",
  },
  {
    label: "Commercial Terms of Service",
    href: "https://www.anthropic.com/legal/commercial-terms",
  },
] as const;

export const REVIEW_DISCLOSURE_SOURCES_NOTE =
  "Sources: Anthropic Privacy Center and Commercial Terms of Service, checked October 18, 2026.";

/** The short line shown beside the Make a review button before anything is sent. */
export function chapterSendsLine(entryCount: number) {
  return `MemoTrail sends the writing of this Chapter and its ${entryCount} ${entryCount === 1 ? "Entry" : "Entries"}, text only, to Anthropic to write the review.`;
}

export function yearSendsLine(entryCount: number, year: number) {
  return `MemoTrail sends the writing of your ${entryCount} ${entryCount === 1 ? "Entry" : "Entries"} from ${year}, text only, to Anthropic to write the review.`;
}

export const REVIEW_FOOTER =
  "Written by Claude, an AI model made by Anthropic, from the Entries above. It is an interpretation, not a record; your Entries are unchanged.";

export const REVIEWS_EXPORT_README_LINE =
  "reviews/*.md contains Chapter and year reviews written by Claude at your request. They are AI interpretation, not your own writing; quotes are copied exactly from your Entries.";
