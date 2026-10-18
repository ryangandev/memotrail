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
  /** Set once MemoTrail refuses the capture; read it through `queuedRejection`. */
  rejection?: QueuedInboxRejection;
  title: string | null;
};

/** Why MemoTrail will never accept a capture, kept with its original content. */
export type QueuedInboxRejection = {
  message: string;
  rejectedAt: string;
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

const maximumQueueSize = 100;
const maximumRejectionMessageLength = 500;
const maximumTimezoneLength = 100;
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function inboxQueueKey(ownerId: string) {
  return `memotrail:inbox-queue:${encodeURIComponent(ownerId)}`;
}

export function inboxQuarantineKey(ownerId: string) {
  return `memotrail:inbox-queue-quarantine:${encodeURIComponent(ownerId)}`;
}

/** Whether a changed storage key belongs to this person's queue or its quarantine. */
export function isInboxQueueStorageKey(key: string, ownerId: string) {
  return key === inboxQueueKey(ownerId) || key === inboxQuarantineKey(ownerId);
}

/** Reads the captures that can be sent. Reading never writes to storage. */
export function loadInboxQueue(
  storage: QueueStorage,
  ownerId: string,
): QueuedInboxEntry[] {
  try {
    return parseInboxQueue(storage.getItem(inboxQueueKey(ownerId))).entries;
  } catch {
    return [];
  }
}

export function enqueueInboxEntry(
  storage: QueueStorage,
  ownerId: string,
  entry: QueuedInboxEntry,
) {
  const state = readQueueState(storage, ownerId);
  if (!state) return null;

  const currentQueue = state.entries;

  if (currentQueue.some((queuedEntry) => queuedEntry.id === entry.id)) {
    return currentQueue;
  }

  if (currentQueue.length >= maximumQueueSize) {
    return null;
  }

  const nextQueue = [...currentQueue, entry];

  return writeQueue(storage, ownerId, state, nextQueue) ? nextQueue : null;
}

export function removeInboxQueueEntry(
  storage: QueueStorage,
  ownerId: string,
  entryId: string,
) {
  const state = readQueueState(storage, ownerId);
  if (!state) return null;

  const nextQueue = state.entries.filter((entry) => entry.id !== entryId);

  return writeQueue(storage, ownerId, state, nextQueue) ? nextQueue : null;
}

/**
 * Marks a capture MemoTrail will never accept, so later runs skip it until the
 * person discards it. A capture another tab already removed stays removed.
 */
export function rejectInboxQueueEntry(
  storage: QueueStorage,
  ownerId: string,
  entryId: string,
  rejection: QueuedInboxRejection,
) {
  const state = readQueueState(storage, ownerId);
  if (!state) return null;

  const currentQueue = state.entries;
  if (!currentQueue.some((entry) => entry.id === entryId)) return currentQueue;

  const nextQueue = currentQueue.map((entry) =>
    entry.id === entryId ? { ...entry, rejection } : entry,
  );

  return writeQueue(storage, ownerId, state, nextQueue) ? nextQueue : null;
}

/**
 * The rejection a capture carries, or null while it waits to sync. A malformed
 * marker never hides the capture; it only lets it be sent again.
 */
export function queuedRejection(
  entry: QueuedInboxEntry,
): QueuedInboxRejection | null {
  const rejection: unknown = entry.rejection;
  if (typeof rejection !== "object" || rejection === null) return null;

  const { message, rejectedAt } = rejection as Partial<QueuedInboxRejection>;
  return typeof message === "string" &&
    message.length > 0 &&
    message.length <= maximumRejectionMessageLength &&
    typeof rejectedAt === "string" &&
    !Number.isNaN(Date.parse(rejectedAt))
    ? { message, rejectedAt }
    : null;
}

/**
 * What a stored queue holds: the captures that can be sent, and every stored
 * item that cannot be read as one. An unreadable item is never dropped; it is
 * kept so the person can copy its writing.
 */
export type ParsedInboxQueue = {
  entries: QueuedInboxEntry[];
  unreadable: unknown[];
};

export function parseInboxQueue(value: string | null): ParsedInboxQueue {
  if (!value) {
    return { entries: [], unreadable: [] };
  }

  let queue: unknown;
  try {
    queue = JSON.parse(value);
  } catch {
    return { entries: [], unreadable: [value] };
  }

  if (!Array.isArray(queue)) {
    return { entries: [], unreadable: [value] };
  }

  const entries: QueuedInboxEntry[] = [];
  const unreadable: unknown[] = [];
  const seen = new Map<string, string>();

  for (const item of queue as unknown[]) {
    const entry = isQueuedInboxEntry(item)
      ? item
      : isLegacyQueuedInboxEntry(item)
        ? { ...item, attachments: [], version: 2 as const }
        : null;
    if (!entry) {
      unreadable.push(item);
      continue;
    }

    const serialized = JSON.stringify(entry);
    const earlier = seen.get(entry.id);
    if (earlier === undefined) {
      seen.set(entry.id, serialized);
      entries.push(entry);
    } else if (earlier !== serialized) {
      // The same id with different content: keep the first and set this aside.
      unreadable.push(item);
    }
  }

  return { entries, unreadable };
}

/** An item that could not be read as a capture, set aside with its date. */
export type QuarantinedCapture = { quarantinedAt: string; value: unknown };

/** An unreadable stored capture as the person sees it. */
export type UnreadableCapture = {
  /** Identifies the item in storage; stable until it is discarded. */
  key: string;
  /** The title and body it holds, or its stored form when it holds neither. */
  text: string;
  value: unknown;
};

const unknownQuarantineDate = new Date(0).toISOString();

function stored(value: unknown) {
  return JSON.stringify(value) ?? "null";
}

function readQueueState(
  storage: QueueStorage,
  ownerId: string,
): ParsedInboxQueue | null {
  try {
    return parseInboxQueue(storage.getItem(inboxQueueKey(ownerId)));
  } catch {
    return null;
  }
}

function readQuarantine(
  storage: QueueStorage,
  ownerId: string,
): QuarantinedCapture[] {
  const value = storage.getItem(inboxQuarantineKey(ownerId));
  if (!value) return [];

  let items: unknown;
  try {
    items = JSON.parse(value);
  } catch {
    // Even a damaged quarantine keeps what it holds.
    return [{ quarantinedAt: unknownQuarantineDate, value }];
  }
  if (!Array.isArray(items))
    return [{ quarantinedAt: unknownQuarantineDate, value }];

  return (items as unknown[]).map((item) =>
    typeof item === "object" &&
    item !== null &&
    "value" in item &&
    typeof (item as QuarantinedCapture).quarantinedAt === "string"
      ? (item as QuarantinedCapture)
      : { quarantinedAt: unknownQuarantineDate, value: item },
  );
}

/** Adds items to the quarantine unless it already holds them. Throws if it cannot. */
function quarantine(storage: QueueStorage, ownerId: string, items: unknown[]) {
  const held = readQuarantine(storage, ownerId);
  const known = new Set(held.map(({ value }) => stored(value)));
  const added: QuarantinedCapture[] = [];
  for (const value of items) {
    const key = stored(value);
    if (known.has(key)) continue;
    known.add(key);
    added.push({ quarantinedAt: new Date().toISOString(), value });
  }
  if (added.length === 0) return;

  storage.setItem(
    inboxQuarantineKey(ownerId),
    JSON.stringify([...held, ...added]),
  );
}

/**
 * Stores the captures that can be sent. Anything unreadable in the stored
 * queue is set aside first, and nothing is written when that fails, so a
 * write can never delete what it could not read.
 */
function writeQueue(
  storage: QueueStorage,
  ownerId: string,
  state: ParsedInboxQueue,
  nextQueue: QueuedInboxEntry[],
) {
  try {
    if (state.unreadable.length > 0)
      quarantine(storage, ownerId, state.unreadable);

    if (nextQueue.length === 0) {
      storage.removeItem(inboxQueueKey(ownerId));
    } else {
      storage.setItem(inboxQueueKey(ownerId), JSON.stringify(nextQueue));
    }
    return true;
  } catch {
    return false;
  }
}

function recoverableText(value: unknown) {
  if (typeof value === "string") return value;
  if (typeof value !== "object" || value === null) return "";

  const { body, bodyRich, title } = value as Record<string, unknown>;
  const richText =
    typeof bodyRich === "object" && bodyRich !== null
      ? (bodyRich as Record<string, unknown>).text
      : undefined;
  return [
    typeof title === "string" ? title : "",
    typeof body === "string" && body
      ? body
      : typeof richText === "string"
        ? richText
        : "",
  ]
    .filter(Boolean)
    .join("\n\n");
}

/** Every stored capture that cannot be sent, in quarantine or still in the queue. */
export function loadUnreadableCaptures(
  storage: QueueStorage,
  ownerId: string,
): UnreadableCapture[] {
  try {
    const state = readQueueState(storage, ownerId);
    const values = [
      ...readQuarantine(storage, ownerId).map(({ value }) => value),
      ...(state?.unreadable ?? []),
    ];
    const seen = new Set<string>();
    return values.flatMap((value) => {
      const key = stored(value);
      if (seen.has(key)) return [];
      seen.add(key);
      return [{ key, text: recoverableText(value) || key, value }];
    });
  } catch {
    return [];
  }
}

/** The photo IDs an unreadable capture refers to, so they stay out of the draft. */
export function unreadableAttachmentIds(value: unknown) {
  if (typeof value !== "object" || value === null) return [];
  const { attachments } = value as { attachments?: unknown };
  if (!Array.isArray(attachments)) return [];
  return (attachments as unknown[]).flatMap((attachment) =>
    typeof attachment === "object" &&
    attachment !== null &&
    typeof (attachment as { id?: unknown }).id === "string"
      ? [(attachment as { id: string }).id]
      : [],
  );
}

/**
 * Removes one unreadable capture for good. Every other unreadable item is set
 * aside first, so only the one the person chose is deleted.
 */
export function discardUnreadableCapture(
  storage: QueueStorage,
  ownerId: string,
  key: string,
) {
  try {
    const state = readQueueState(storage, ownerId);
    if (!state) return false;

    const kept: QuarantinedCapture[] = [];
    const seen = new Set<string>();
    for (const item of [
      ...readQuarantine(storage, ownerId),
      ...state.unreadable.map((value) => ({
        quarantinedAt: new Date().toISOString(),
        value,
      })),
    ]) {
      const itemKey = stored(item.value);
      if (itemKey === key || seen.has(itemKey)) continue;
      seen.add(itemKey);
      kept.push(item);
    }

    if (kept.length === 0) storage.removeItem(inboxQuarantineKey(ownerId));
    else storage.setItem(inboxQuarantineKey(ownerId), JSON.stringify(kept));

    // The queue only loses items that are now safe in the quarantine.
    if (state.unreadable.length > 0) {
      if (state.entries.length === 0)
        storage.removeItem(inboxQueueKey(ownerId));
      else
        storage.setItem(inboxQueueKey(ownerId), JSON.stringify(state.entries));
    }
    return true;
  } catch {
    return false;
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
