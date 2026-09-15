import { entryBodyLimit, entryTitleLimit } from "./inbox-input";
import { occurrencePrecisions, type OccurrenceDraft } from "./occurrence";
import { isEntryRichText, type EntryRichText } from "./rich-text";

export type InboxDraft = {
  body: string;
  occurredAt: string | null;
  title: string;
  updatedAt: string;
  occurrence?: OccurrenceDraft | null;
  bodyRich?: EntryRichText | null;
  version: 2 | 3;
};

export type DraftStorage = Pick<Storage, "getItem" | "removeItem" | "setItem">;

export function inboxDraftKey(ownerId: string) {
  return `memotrail:inbox-draft:${encodeURIComponent(ownerId)}`;
}

export function loadInboxDraft(
  storage: DraftStorage,
  ownerId: string,
): InboxDraft | null {
  try {
    return parseInboxDraft(storage.getItem(inboxDraftKey(ownerId)));
  } catch {
    return null;
  }
}

export function persistInboxDraft(
  storage: DraftStorage,
  ownerId: string,
  values: Pick<
    InboxDraft,
    "body" | "bodyRich" | "occurredAt" | "title" | "occurrence"
  >,
) {
  const hasContent = Boolean(values.title || values.body || values.occurrence);

  try {
    if (!hasContent) {
      storage.removeItem(inboxDraftKey(ownerId));
      return false;
    }

    const draft: InboxDraft = {
      ...values,
      updatedAt: new Date().toISOString(),
      version: values.occurrence === undefined ? 2 : 3,
    };

    storage.setItem(inboxDraftKey(ownerId), JSON.stringify(draft));
    return true;
  } catch {
    return false;
  }
}

export function clearInboxDraft(storage: DraftStorage, ownerId: string) {
  try {
    storage.removeItem(inboxDraftKey(ownerId));
  } catch {
    // A blocked browser storage API should never prevent a successful save.
  }
}

export function parseInboxDraft(value: string | null): InboxDraft | null {
  if (!value) {
    return null;
  }

  try {
    const draft = JSON.parse(value) as {
      body?: unknown;
      occurredAt?: unknown;
      title?: unknown;
      updatedAt?: unknown;
      version?: unknown;
      occurrence?: unknown;
      bodyRich?: unknown;
    };

    if (
      ![1, 2, 3].includes(draft.version as number) ||
      typeof draft.title !== "string" ||
      typeof draft.body !== "string" ||
      typeof draft.updatedAt !== "string" ||
      draft.title.length > entryTitleLimit ||
      draft.body.length > entryBodyLimit ||
      Number.isNaN(Date.parse(draft.updatedAt)) ||
      (!draft.title && !draft.body && !draft.occurrence)
    ) {
      return null;
    }

    if (
      draft.version === 3 &&
      draft.occurrence !== null &&
      !isCaptureOccurrenceDraft(draft.occurrence)
    )
      return null;

    if (
      draft.bodyRich !== undefined &&
      draft.bodyRich !== null &&
      !isEntryRichText(draft.bodyRich, draft.body)
    ) {
      return null;
    }

    const occurredAt = draft.version === 1 ? null : draft.occurredAt;

    if (
      occurredAt !== null &&
      (typeof occurredAt !== "string" || Number.isNaN(Date.parse(occurredAt)))
    ) {
      return null;
    }

    return {
      body: draft.body,
      occurredAt,
      title: draft.title,
      updatedAt: draft.updatedAt,
      version: 2,
      ...(draft.bodyRich === undefined
        ? {}
        : { bodyRich: draft.bodyRich as EntryRichText | null }),
      ...(draft.version === 3
        ? {
            version: 3 as const,
            occurrence: draft.occurrence as OccurrenceDraft | null,
          }
        : {}),
    };
  } catch {
    return null;
  }
}

// An unfinished date must survive closing the composer; semantic validation is
// deferred until Save. A temporarily invalid field must not discard the writing.
export function isCaptureOccurrenceDraft(
  value: unknown,
): value is OccurrenceDraft {
  if (!value || typeof value !== "object") return false;
  const draft = value as Partial<OccurrenceDraft>;
  return (
    occurrencePrecisions.includes(draft.precision!) &&
    typeof draft.start === "string" &&
    typeof draft.end === "string" &&
    (draft.endMode === undefined ||
      draft.endMode === "date" ||
      draft.endMode === "present") &&
    typeof draft.label === "string" &&
    typeof draft.timezone === "string"
  );
}
