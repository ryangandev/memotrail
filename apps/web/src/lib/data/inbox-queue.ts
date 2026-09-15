import { entryBodyLimit, entryTitleLimit } from "./inbox-input";
import { validateOccurrence, type Occurrence } from "./occurrence";
import {
  inboxPhotoLimit,
  isQueuedInboxAttachment,
  type QueuedInboxAttachment,
} from "./inbox-photo";
import { isEntryRichText, type EntryRichText } from "./rich-text";

type QueueEntryBase = {
  attachments: QueuedInboxAttachment[];
  body: string;
  bodyRich?: EntryRichText | null;
  id: string;
  occurredTimezone: string;
  queuedAt: string;
  title: string | null;
};
export type QueuedInboxEntry = QueueEntryBase &
  ({ version: 2; occurredAt: string } | ({ version: 3 } & Occurrence));

export function queuedOccurrence(entry: QueuedInboxEntry): Occurrence {
  return entry.version === 3
    ? entry
    : {
        occurredAt: entry.occurredAt,
        occurredTimezone: entry.occurredTimezone,
        occurredEnd: null,
        occurredLabel: null,
        datePrecision: "exact",
      };
}

type LegacyQueuedInboxEntry = Omit<
  QueueEntryBase,
  "attachments" | "version"
> & {
  version: 1;
  occurredAt: string;
};

export type QueueStorage = Pick<Storage, "getItem" | "removeItem" | "setItem">;

export const inboxQueueChangedEvent = "memotrail:inbox-queue-changed";

const maximumQueueSize = 100;
const maximumTimezoneLength = 100;
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function inboxQueueKey(ownerId: string) {
  return `memotrail:inbox-queue:${encodeURIComponent(ownerId)}`;
}

export function loadInboxQueue(
  storage: QueueStorage,
  ownerId: string,
): QueuedInboxEntry[] {
  try {
    return parseInboxQueue(storage.getItem(inboxQueueKey(ownerId)));
  } catch {
    return [];
  }
}

export function enqueueInboxEntry(
  storage: QueueStorage,
  ownerId: string,
  entry: QueuedInboxEntry,
) {
  const currentQueue = loadInboxQueue(storage, ownerId);

  if (currentQueue.some((queuedEntry) => queuedEntry.id === entry.id)) {
    return currentQueue;
  }

  if (currentQueue.length >= maximumQueueSize) {
    return null;
  }

  const nextQueue = [...currentQueue, entry];

  try {
    storage.setItem(inboxQueueKey(ownerId), JSON.stringify(nextQueue));
    return nextQueue;
  } catch {
    return null;
  }
}

export function removeInboxQueueEntry(
  storage: QueueStorage,
  ownerId: string,
  entryId: string,
) {
  const nextQueue = loadInboxQueue(storage, ownerId).filter(
    (entry) => entry.id !== entryId,
  );

  try {
    if (nextQueue.length === 0) {
      storage.removeItem(inboxQueueKey(ownerId));
    } else {
      storage.setItem(inboxQueueKey(ownerId), JSON.stringify(nextQueue));
    }

    return nextQueue;
  } catch {
    return null;
  }
}

export function parseInboxQueue(value: string | null): QueuedInboxEntry[] {
  if (!value) {
    return [];
  }

  try {
    const queue = JSON.parse(value) as unknown;

    if (!Array.isArray(queue) || queue.length > maximumQueueSize) {
      return [];
    }

    const parsedQueue = queue.flatMap((entry) => {
      if (isQueuedInboxEntry(entry)) {
        return [entry];
      }

      if (isLegacyQueuedInboxEntry(entry)) {
        return [{ ...entry, attachments: [], version: 2 as const }];
      }

      return [];
    });
    const uniqueIds = new Set(parsedQueue.map((entry) => entry.id));

    return uniqueIds.size === parsedQueue.length ? parsedQueue : [];
  } catch {
    return [];
  }
}

export function isQueuedInboxEntry(value: unknown): value is QueuedInboxEntry {
  if (typeof value !== "object" || value === null) {
    return false;
  }

  const entry = value as Partial<QueuedInboxEntry>;
  const attachments = Array.isArray(entry.attachments)
    ? entry.attachments.filter(isQueuedInboxAttachment)
    : [];
  const uniqueAttachmentIds = new Set(
    attachments.map((attachment) => attachment.id),
  );

  return (
    (entry.version === 2 || entry.version === 3) &&
    typeof entry.id === "string" &&
    uuidPattern.test(entry.id) &&
    (entry.title === null ||
      (typeof entry.title === "string" &&
        entry.title.length > 0 &&
        entry.title.length <= entryTitleLimit)) &&
    typeof entry.body === "string" &&
    entry.body.length <= entryBodyLimit &&
    (entry.bodyRich === undefined ||
      entry.bodyRich === null ||
      isEntryRichText(entry.bodyRich, entry.body)) &&
    Array.isArray(entry.attachments) &&
    attachments.length === entry.attachments.length &&
    attachments.length <= inboxPhotoLimit &&
    uniqueAttachmentIds.size === attachments.length &&
    Boolean(entry.title || entry.body || attachments.length > 0) &&
    (entry.version === 3
      ? validateOccurrence(entry as Occurrence) === null
      : typeof entry.occurredAt === "string" &&
        !Number.isNaN(Date.parse(entry.occurredAt))) &&
    typeof entry.queuedAt === "string" &&
    !Number.isNaN(Date.parse(entry.queuedAt)) &&
    typeof entry.occurredTimezone === "string" &&
    entry.occurredTimezone.length > 0 &&
    entry.occurredTimezone.length <= maximumTimezoneLength
  );
}

function isLegacyQueuedInboxEntry(
  value: unknown,
): value is LegacyQueuedInboxEntry {
  if (typeof value !== "object" || value === null) {
    return false;
  }

  const entry = value as Partial<LegacyQueuedInboxEntry>;

  return (
    entry.version === 1 &&
    typeof entry.id === "string" &&
    uuidPattern.test(entry.id) &&
    (entry.title === null ||
      (typeof entry.title === "string" &&
        entry.title.length > 0 &&
        entry.title.length <= entryTitleLimit)) &&
    typeof entry.body === "string" &&
    entry.body.length <= entryBodyLimit &&
    Boolean(entry.title || entry.body) &&
    typeof entry.occurredAt === "string" &&
    !Number.isNaN(Date.parse(entry.occurredAt)) &&
    typeof entry.queuedAt === "string" &&
    !Number.isNaN(Date.parse(entry.queuedAt)) &&
    typeof entry.occurredTimezone === "string" &&
    entry.occurredTimezone.length > 0 &&
    entry.occurredTimezone.length <= maximumTimezoneLength
  );
}
