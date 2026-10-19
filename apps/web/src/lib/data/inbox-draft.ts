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

/** The draft, and whether everything stored for it could be read. */
export type InboxDraftReading = {
  draft: InboxDraft | null;
  /** False when reading lost part of the stored draft, such as an overlong body. */
  isComplete: boolean;
};

export function inboxDraftKey(ownerId: string) {
  return `memotrail:inbox-draft:${encodeURIComponent(ownerId)}`;
}

export function inboxDraftQuarantineKey(ownerId: string) {
  return `memotrail:inbox-draft-quarantine:${encodeURIComponent(ownerId)}`;
}

/** Reads the draft; reading never writes to storage. */
export function loadInboxDraft(
  storage: DraftStorage,
  ownerId: string,
): InboxDraft | null {
  return readInboxDraft(storage, ownerId).draft;
}

export function readInboxDraft(
  storage: DraftStorage,
  ownerId: string,
): InboxDraftReading {
  try {
    return inspectInboxDraft(storage.getItem(inboxDraftKey(ownerId)));
  } catch {
    return { draft: null, isComplete: true };
  }
}

// The exact text this module last stored or checked for each draft, so a
// keystroke does not read back and validate what it wrote itself.
const checkedDrafts = new WeakMap<object, Map<string, string>>();

/**
 * Before a draft is replaced or removed, sets the stored text aside if
 * reading it would lose any of it. Throws when it cannot, so the caller
 * leaves the stored draft alone.
 */
function keepUnreadableDraft(storage: DraftStorage, ownerId: string) {
  const key = inboxDraftKey(ownerId);
  const stored = storage.getItem(key);
  if (!stored) return;

  const checked = checkedDrafts.get(storage) ?? new Map<string, string>();
  checkedDrafts.set(storage, checked);
  if (checked.get(key) === stored) return;

  if (!inspectInboxDraft(stored).isComplete) {
    const quarantineKey = inboxDraftQuarantineKey(ownerId);
    const held = parseQuarantinedDrafts(storage.getItem(quarantineKey));
    if (!held.some(({ value }) => value === stored))
      storage.setItem(
        quarantineKey,
        JSON.stringify([
          ...held,
          { quarantinedAt: new Date().toISOString(), value: stored },
        ]),
      );
  }
  checked.set(key, stored);
}

function parseQuarantinedDrafts(
  value: string | null,
): { quarantinedAt: string; value: string }[] {
  if (!value) return [];
  try {
    const items: unknown = JSON.parse(value);
    if (Array.isArray(items))
      return items as { quarantinedAt: string; value: string }[];
  } catch {
    // A damaged quarantine is kept as it is, below.
  }
  return [{ quarantinedAt: new Date(0).toISOString(), value }];
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
    keepUnreadableDraft(storage, ownerId);

    if (!hasContent) {
      storage.removeItem(inboxDraftKey(ownerId));
      return false;
    }

    const draft: InboxDraft = {
      ...values,
      updatedAt: new Date().toISOString(),
      version: values.occurrence === undefined ? 2 : 3,
    };
    const serialized = JSON.stringify(draft);

    storage.setItem(inboxDraftKey(ownerId), serialized);
    checkedDrafts.get(storage)?.set(inboxDraftKey(ownerId), serialized);
    return true;
  } catch {
    return false;
  }
}

export function clearInboxDraft(storage: DraftStorage, ownerId: string) {
  try {
    keepUnreadableDraft(storage, ownerId);
    storage.removeItem(inboxDraftKey(ownerId));
  } catch {
    // A blocked browser storage API should never prevent a successful save.
  }
}

export function parseInboxDraft(value: string | null): InboxDraft | null {
  return inspectInboxDraft(value).draft;
}

/**
 * Reads whatever part of a stored draft is usable. Writing that breaks a rule
 * of today's release, such as a body over the limit, still comes back, cut to
 * the limit, instead of the whole draft disappearing. `isComplete` is false
 * then, so the original is kept aside before it is replaced.
 */
export function inspectInboxDraft(value: string | null): InboxDraftReading {
  if (!value) {
    return { draft: null, isComplete: true };
  }

  let stored: unknown;
  try {
    stored = JSON.parse(value);
  } catch {
    return { draft: null, isComplete: false };
  }
  if (typeof stored !== "object" || stored === null) {
    return { draft: null, isComplete: false };
  }

  const draft = stored as {
    body?: unknown;
    occurredAt?: unknown;
    title?: unknown;
    updatedAt?: unknown;
    version?: unknown;
    occurrence?: unknown;
    bodyRich?: unknown;
  };
  let isComplete = [1, 2, 3].includes(draft.version as number);

  let title = "";
  if (typeof draft.title === "string") {
    title = draft.title.slice(0, entryTitleLimit);
    if (title.length !== draft.title.length) isComplete = false;
  } else isComplete = false;

  let body = "";
  if (typeof draft.body === "string") {
    body = draft.body.slice(0, entryBodyLimit);
    if (body.length !== draft.body.length) isComplete = false;
  } else isComplete = false;

  let updatedAt = new Date(0).toISOString();
  if (
    typeof draft.updatedAt === "string" &&
    !Number.isNaN(Date.parse(draft.updatedAt))
  )
    updatedAt = draft.updatedAt;
  else isComplete = false;

  let occurrence: OccurrenceDraft | null | undefined;
  if (draft.version === 3) {
    if (draft.occurrence === null || isCaptureOccurrenceDraft(draft.occurrence))
      occurrence = draft.occurrence;
    else isComplete = false;
  }

  let bodyRich: EntryRichText | null | undefined;
  if (draft.bodyRich === undefined || draft.bodyRich === null)
    bodyRich = draft.bodyRich;
  else if (isEntryRichText(draft.bodyRich, body)) bodyRich = draft.bodyRich;
  else isComplete = false;

  let occurredAt: string | null = null;
  if (draft.version !== 1) {
    if (
      typeof draft.occurredAt === "string" &&
      !Number.isNaN(Date.parse(draft.occurredAt))
    )
      occurredAt = draft.occurredAt;
    else if (draft.occurredAt !== null) isComplete = false;
  }

  if (!title && !body && !occurrence) return { draft: null, isComplete };

  return {
    draft: {
      body,
      occurredAt,
      title,
      updatedAt,
      version: 2,
      ...(bodyRich === undefined ? {} : { bodyRich }),
      ...(occurrence === undefined ? {} : { version: 3 as const, occurrence }),
    },
    isComplete,
  };
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
