import type { Occurrence } from "./occurrence";

// What a Chapter's page shows, kept apart from the loader so client components can use it
// without pulling in the server-only code that signs photo URLs.

/** How many Entries one page of a Chapter lists. */
export const chapterEntriesPageSize = 50;

export type ChapterCoverPhoto = {
  alt: string;
  /** Signed for display, or null when the photo cannot be shown. */
  imageUrl: string | null;
  objectPath: string;
};

/** An Entry dated inside a Chapter. */
export type ChapterEntry = {
  coverPhoto: ChapterCoverPhoto | null;
  excerpt: string;
  id: string;
  isFirstTime: boolean;
  occurrence: Occurrence;
  tagNames: string[];
  /** The stored title, blank when the Entry has none. */
  title: string;
};

/** A Chapter or First Time whose days overlap this Chapter's. */
export type ChapterOverlap = {
  id: string;
  isFirstTime: boolean;
  occurrence: Occurrence;
  /** Its title, or its date when it has none. */
  title: string;
};

export type ChapterContents = {
  entries: ChapterEntry[];
  /** True when the Entries could not load. */
  failed: boolean;
  overlaps: ChapterOverlap[];
  totalCount: number;
};
