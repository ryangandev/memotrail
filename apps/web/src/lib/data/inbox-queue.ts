import { entryBodyLimit, entryTitleLimit } from "./inbox-input";

export type QueuedInboxEntry = {
  body: string;
  id: string;
  occurredAt: string;
  occurredTimezone: string;
  queuedAt: string;
  title: string | null;
  version: 1;
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

    const parsedQueue = queue.filter(isQueuedInboxEntry);
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
