import { entryBodyLimit, entryTitleLimit } from "./inbox-input";

export const reviewableEntryTypes = ["standard", "first_time"] as const;
export type ReviewableEntryType = (typeof reviewableEntryTypes)[number];

export type InboxReviewInput = {
  body: string;
  entryType: ReviewableEntryType;
  id: string;
  occurredAt: string;
  occurredTimezone: string;
  revision: number;
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
  const title = typeof values.title === "string" ? values.title.trim() : "";
  const body = typeof values.body === "string" ? values.body.trim() : "";

  if (!title && !body) {
    return invalidReview("Keep a title or note before saving.");
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

  if (
    typeof values.occurredAt !== "string" ||
    Number.isNaN(Date.parse(values.occurredAt))
  ) {
    return invalidReview("Choose a valid date and time.");
  }

  if (
    typeof values.occurredTimezone !== "string" ||
    !values.occurredTimezone ||
    values.occurredTimezone.length > 100
  ) {
    return invalidReview("Choose a valid time zone.");
  }

  return {
    data: {
      body,
      entryType: values.entryType as ReviewableEntryType,
      id: values.id,
      occurredAt: new Date(values.occurredAt).toISOString(),
      occurredTimezone: values.occurredTimezone,
      revision: values.revision,
      title: title || null,
    },
    success: true,
  };
}

function invalidReview(message: string): InboxReviewInputResult {
  return { message, success: false };
}
