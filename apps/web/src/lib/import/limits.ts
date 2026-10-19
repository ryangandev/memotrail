import {
  entryPhotoLimit,
  entryPhotoSizeLimit,
} from "@/lib/data/entry-photo-input";
import { entryBodyLimit, entryTitleLimit } from "@/lib/data/inbox-input";
import { tagNameCountLimit, tagNameLengthLimit } from "@/lib/data/organization";

const mebibyte = 1024 * 1024;
const gibibyte = 1024 * mebibyte;

/** The staged ZIP size when IMPORT_MAX_ZIP_BYTES is not set: the Supabase free plan's file limit. */
export const defaultImportMaxZipBytes = 50 * mebibyte;
/** Never accept a larger value from the setting, whatever the Storage limit allows. */
export const importMaxZipBytesCeiling = 5 * gibibyte;

/**
 * The size of ZIP a person may import. A larger cap needs the hosted project's Storage file
 * size limit raised first, because Storage refuses the upload before the Web server sees it.
 */
export function importMaxZipBytes(
  setting: string | undefined = process.env.IMPORT_MAX_ZIP_BYTES,
): number {
  const parsed = setting ? Number(setting.trim()) : Number.NaN;
  if (!Number.isSafeInteger(parsed) || parsed < mebibyte)
    return defaultImportMaxZipBytes;
  return Math.min(parsed, importMaxZipBytesCeiling);
}

export const importLimits = {
  /** An import is one job at a time per person, enforced by the database. */
  maxEntriesPerJob: 20_000,
  maxPhotosPerJob: 10_000,
  maxPhotoBytes: entryPhotoSizeLimit,
  /** Photos one Entry can hold in the editor. More are skipped and counted. */
  maxPhotosPerEntry: entryPhotoLimit,
  maxTextFileBytes: 5 * mebibyte,
  maxCsvBytes: 20 * mebibyte,
  /** A Day One journal is one JSON file holding every entry. */
  maxJournalJsonBytes: 256 * mebibyte,
  maxZipMembers: 200_000,
  maxUncompressedBytes: 25 * gibibyte,
  /** A member this much larger than its compressed size, past the size below, is refused. */
  maxCompressionRatio: 200,
  ratioCheckMinBytes: 100 * mebibyte,
  /** Nested ZIPs (a Notion export of parts) are opened one level deep and held in memory. */
  maxNestedZipBytes: 256 * mebibyte,
  titleChars: entryTitleLimit,
  bodyChars: entryBodyLimit,
  tagsPerEntry: tagNameCountLimit,
  tagChars: tagNameLengthLimit,
  /** Folder tags are offered only while there are not too many distinct folders. */
  maxFolderTags: 30,
  maxPreviewFolders: 2_000,
  sampleEntries: 20,
  /** A body is cut into parts below the limit so the rich text stays valid. */
  partChars: 45_000,
  partNodes: 3_200,
  partBytes: 180_000,
  photoUploadConcurrency: 3,
  photoUploadAttempts: 3,
  /** One run call stops starting new items after this long. */
  runBudgetMs: 240_000,
  runLeaseSeconds: 300,
  claimBatch: 10,
  scanBatch: 200,
} as const;
