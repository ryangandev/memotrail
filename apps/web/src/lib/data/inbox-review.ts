import { entryBodyLimit, entryTitleLimit } from "./inbox-input";
import { validPhotoPlace, type PhotoPlaceDraft } from "@/lib/media/photo-place";
import { validateOccurrence, type OccurrencePrecision } from "./occurrence";

export const reviewableEntryTypes = ["standard", "first_time"] as const;
export type ReviewableEntryType = (typeof reviewableEntryTypes)[number];

export type InboxReviewInput = {
  photoPlace?: PhotoPlaceDraft | null;
  body: string;
  collectionNames: string[];
  entryType: ReviewableEntryType;
  id: string;
  occurredAt: string | null;
  occurredEnd?: string | null;
  occurredLabel?: string | null;
  datePrecision?: OccurrencePrecision;
  occurredTimezone: string;
  revision: number;
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
  if (values.photoPlace != null && !validPhotoPlace(values.photoPlace))
    return invalidReview(
      "Review the Place name and coordinates, or remove it from this draft.",
    );
  const title = typeof values.title === "string" ? values.title.trim() : "";
  const body = typeof values.body === "string" ? values.body.trim() : "";
  const collectionNames = parseOrganizationNames(
    values.collectionNames,
    20,
    80,
  );
  const tagNames = parseOrganizationNames(values.tagNames, 50, 60);

  if (!title && !body) {
    return invalidReview("Keep a title or note before saving.");
  }

  if (!collectionNames) {
    return invalidReview(
      "Use up to 20 Collections with names under 80 characters.",
    );
  }

  if (!tagNames) {
    return invalidReview("Use up to 50 tags with names under 60 characters.");
  }

  if (title.length > entryTitleLimit) {
    return invalidReview(`Keep the title under ${entryTitleLimit} characters.`);
  }

  if (body.length > entryBodyLimit) {
    return invalidReview(
      `Keep the note under ${entryBodyLimit.toLocaleString("en-US")} characters.`,
    );
  }

  if (
    typeof values.id !== "string" ||
    !uuidPattern.test(values.id) ||
    typeof values.revision !== "number" ||
    !Number.isInteger(values.revision) ||
    values.revision < 1
  ) {
    return invalidReview("This Entry review is invalid.");
  }

  if (
    typeof values.entryType !== "string" ||
    !reviewableEntryTypes.includes(values.entryType as ReviewableEntryType)
  ) {
    return invalidReview("Choose a supported Entry type.");
  }

  if (values.entryType === "first_time" && !title) {
    return invalidReview(
      "Add a title before marking an Entry as a First Time.",
    );
  }

  const occurrence = {
    occurredAt: values.occurredAt as string | null,
    occurredEnd: (values.occurredEnd ?? null) as string | null,
    occurredLabel: (values.occurredLabel ?? null) as string | null,
    occurredTimezone: values.occurredTimezone as string,
    datePrecision: (values.datePrecision ?? "exact") as OccurrencePrecision,
  };
  const occurrenceError = validateOccurrence(occurrence);
  if (occurrenceError) return invalidReview(occurrenceError);

  return {
    data: {
      ...(values.photoPlace != null
        ? { photoPlace: values.photoPlace as PhotoPlaceDraft }
        : {}),
      body,
      collectionNames,
      entryType: values.entryType as ReviewableEntryType,
      id: values.id,
      ...occurrence,
      occurredAt: occurrence.occurredAt,
      occurredEnd: occurrence.occurredEnd,
      occurredLabel: occurrence.occurredLabel?.trim() || null,
      revision: values.revision,
      tagNames,
      title: title || null,
    },
    success: true,
  };
}

export function parseOrganizationNames(
  input: unknown,
  maximumCount: number,
  maximumNameLength: number,
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
