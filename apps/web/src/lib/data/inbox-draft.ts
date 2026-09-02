import { entryBodyLimit, entryTitleLimit } from "./inbox-input";

export type InboxDraft = {
  body: string;
  title: string;
  updatedAt: string;
  version: 1;
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
  values: Pick<InboxDraft, "body" | "title">,
) {
  const hasContent = Boolean(values.title || values.body);

  try {
    if (!hasContent) {
      storage.removeItem(inboxDraftKey(ownerId));
      return false;
    }

    const draft: InboxDraft = {
      ...values,
      updatedAt: new Date().toISOString(),
      version: 1,
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
    const draft = JSON.parse(value) as Partial<InboxDraft>;

    if (
      draft.version !== 1 ||
      typeof draft.title !== "string" ||
      typeof draft.body !== "string" ||
      typeof draft.updatedAt !== "string" ||
      draft.title.length > entryTitleLimit ||
      draft.body.length > entryBodyLimit ||
      Number.isNaN(Date.parse(draft.updatedAt)) ||
      (!draft.title && !draft.body)
    ) {
      return null;
    }

    return draft as InboxDraft;
  } catch {
    return null;
  }
}
