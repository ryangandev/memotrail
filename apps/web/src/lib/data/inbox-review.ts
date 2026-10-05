import { entryBodyLimit, entryTitleLimit } from "./inbox-input";
import {
  validLocationSelection,
  type LocationSelection,
} from "@/lib/locations/location";
import {
  validPhotoLocation,
  type PhotoLocationDraft,
} from "@/lib/media/photo-location";
import { validateOccurrence, type OccurrencePrecision } from "./occurrence";
import { isMilestone, type Milestone } from "./milestone";
import { isEntryRichText, type EntryRichText } from "./rich-text";
import {
  tagNameCountLimit,
  tagNameLengthLimit,
  tagNamesLimitMessage,
} from "./organization";

export type InboxReviewInput = {
  location: LocationSelection | null;
  photoLocation?: PhotoLocationDraft | null;
  body: string;
  bodyRich?: EntryRichText | null;
  id: string;
  milestone?: Milestone | null;
  occurredAt: string | null;
  occurredEnd?: string | null;
  occurredLabel?: string | null;
  datePrecision?: OccurrencePrecision;
  occurredTimezone: string;
  // Null saves a new Entry with `id`.
  revision: number | null;
  tagNames: string[];
  title: string | null;
};

export type InboxReviewInputResult =
  | { data: InboxReviewInput; success: true }
  | { message: string; success: false };

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function parseInboxReviewInput(input: unknown): InboxReviewInputResult {
  if (typeof input !== "object" || input === null) {
    return invalidReview("This Entry review is invalid.");
  }

  const values = input as Partial<Record<keyof InboxReviewInput, unknown>>;
  if (values.location != null && !validLocationSelection(values.location))
    return invalidReview(
      "Choose a valid Location or remove it from this Entry.",
    );
  if (values.photoLocation != null && !validPhotoLocation(values.photoLocation))
    return invalidReview(
      "Choose the photo's GPS position again, or remove it from this draft.",
    );
  if (values.milestone != null && !isMilestone(values.milestone))
    return invalidReview("Choose how this Entry appears on Timeline.");
  const milestone = (values.milestone ?? null) as Milestone | null;
  const title = typeof values.title === "string" ? values.title.trim() : "";
  const body = typeof values.body === "string" ? values.body.trim() : "";
  const bodyRich =
    values.bodyRich === null || values.bodyRich === undefined
      ? null
      : isEntryRichText(values.bodyRich, body)
        ? values.bodyRich
        : undefined;
  const tagNames = parseTagNames(values.tagNames);

  if (!title && !body) {
    return invalidReview("Keep a title or note before saving.");
  }

  if (bodyRich === undefined) {
    // `trimEntryNote` sends formatting for exactly the trimmed note, so only a stale or
    // malformed document reaches this. Editing the note produces a matching one.
    return invalidReview(
      "MemoTrail could not keep this note's formatting. Edit the note, then save again.",
    );
  }

  if (!tagNames) {
    return invalidReview(tagNamesLimitMessage);
  }

  if (title.length > entryTitleLimit) {
    return invalidReview(`Keep the title under ${entryTitleLimit} characters.`);
  }

  if (body.length > entryBodyLimit) {
    return invalidReview(
      `Keep the note under ${entryBodyLimit.toLocaleString("en-US")} characters.`,
    );
  }

  const revision = values.revision;
  if (
    typeof values.id !== "string" ||
    !uuidPattern.test(values.id) ||
    (revision !== null &&
      (typeof revision !== "number" ||
        !Number.isInteger(revision) ||
        revision < 1)) ||
    // A new Entry has no photos yet.
    (revision === null && values.photoLocation != null)
  ) {
    return invalidReview("This Entry review is invalid.");
  }

  const occurrence = {
    occurredAt: values.occurredAt as string | null,
    occurredEnd: (values.occurredEnd ?? null) as string | null,
    occurredLabel: (values.occurredLabel ?? null) as string | null,
    occurredTimezone: values.occurredTimezone as string,
    datePrecision: (values.datePrecision ?? "exact") as OccurrencePrecision,
  };
  const occurrenceError = validateOccurrence(
    occurrence,
    milestone?.shape === "period",
  );
  if (occurrenceError) return invalidReview(occurrenceError);
  if (
    milestone?.shape === "moment" &&
    (occurrence.occurredEnd || occurrence.datePrecision === "range")
  )
    return invalidReview(
      "A Moment is one point in time. Remove the end date, or make it a Period.",
    );

  return {
    data: {
      ...(values.photoLocation != null
        ? { photoLocation: values.photoLocation as PhotoLocationDraft }
        : {}),
      body,
      bodyRich,
      id: values.id,
      location: (values.location ?? null) as LocationSelection | null,
      milestone,
      ...occurrence,
      occurredAt: occurrence.occurredAt,
      occurredEnd: occurrence.occurredEnd,
      occurredLabel: occurrence.occurredLabel?.trim() || null,
      revision: revision as number | null,
      tagNames,
      title: title || null,
    },
    success: true,
  };
}

export function parseTagNames(
  input: unknown,
  maximumCount = tagNameCountLimit,
  maximumNameLength = tagNameLengthLimit,
) {
  if (!Array.isArray(input) || input.length > maximumCount) {
    return null;
  }

  const names: string[] = [];
  const normalizedNames = new Set<string>();

  for (const value of input) {
    if (typeof value !== "string") {
      return null;
    }

    const name = value.trim();
    const normalizedName = name.toLocaleLowerCase();

    if (!name || name.length > maximumNameLength) {
      return null;
    }

    if (!normalizedNames.has(normalizedName)) {
      normalizedNames.add(normalizedName);
      names.push(name);
    }
  }

  return names;
}

function invalidReview(message: string): InboxReviewInputResult {
  return { message, success: false };
}
