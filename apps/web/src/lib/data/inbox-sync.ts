import type { PhotoUploadProgress } from "@/lib/media/upload";
import {
  enqueueInboxEntry,
  loadInboxQueue,
  removeInboxQueueEntry,
  type QueueStorage,
  type QueuedInboxEntry,
} from "./inbox-queue";

export type InboxSyncResult = {
  message: string;
  status: "retry" | "synced";
};

/** The network side of one capture's synchronization. */
export type InboxSyncTransport = {
  /** Inserts the Entry; an Entry that already reached MemoTrail reports synced. */
  syncEntry: (entry: QueuedInboxEntry) => Promise<InboxSyncResult>;
  /** Uploads and registers the capture's photos after its Entry exists. */
  syncAttachments: (
    entry: QueuedInboxEntry,
    onProgress: (progress: PhotoUploadProgress) => void,
  ) => Promise<InboxSyncResult>;
  /** Runs once a capture with photos is complete. */
  finishCapture: (entryId: string) => Promise<void>;
};

export type PendingCaptureStatus = "syncing" | "waiting";

export type PendingCapture = {
  entry: QueuedInboxEntry;
  status: PendingCaptureStatus;
  /**
   * Captured in this tab while online and still inside its first sync attempt.
   * Such a brief local queue stage is progress, not a Pending sync list.
   */
  firstAttempt: boolean;
};

export type InboxSyncSnapshot = {
  /** False until this browser's queue has been read. */
  isReady: boolean;
  isSyncing: boolean;
  items: readonly PendingCapture[];
  /** The problem that ended the latest sync run, until a later run clears it. */
  lastError: string | null;
  photoUploadProgress: PhotoUploadProgress | null;
  /** Counts finished sync runs, so a composer can dismiss one run's problem. */
  runCount: number;
};

export type InboxSyncRun = {
  /** The final attempt's result, or null when nothing needed to sync. */
  result: InboxSyncResult | null;
  synced: number;
};

export type InboxSyncStore = {
  /** Stores a capture on this device, then starts its synchronization. */
  enqueue: (entry: QueuedInboxEntry) => QueuedInboxEntry[] | null;
  getServerSnapshot: () => InboxSyncSnapshot;
  getSnapshot: () => InboxSyncSnapshot;
  onRunFinished: (listener: (run: InboxSyncRun) => void) => () => void;
  /**
   * Rereads the queue after another tab changed it, returning how many
   * captures left it, which means that tab synced them.
   */
  reload: () => number;
  subscribe: (listener: () => void) => () => void;
  /** Never rejects; problems are reported through the snapshot. */
  synchronize: () => Promise<void>;
};

export const offlineSyncMessage =
  "Saved on this device. MemoTrail will retry when you are online.";
const offlinePhotoSyncMessage =
  "Photos are saved on this device. MemoTrail will retry when you are online.";
const uncleanedQueueMessage =
  "This Entry reached MemoTrail, but its local pending copy could not be cleared.";

const serverSnapshot: InboxSyncSnapshot = {
  isReady: false,
  isSyncing: false,
  items: [],
  lastError: null,
  photoUploadProgress: null,
  runCount: 0,
};

/**
 * Owns one person's pending captures in this browser tab. Runs are serialized
 * in the tab and, through `runExclusive`, across tabs that share the queue.
 * Each run sends captures oldest first and stops at the first one that must
 * wait, rereading the shared queue before every capture.
 */
export function createInboxSyncStore({
  isOnline = () => true,
  ownerId,
  runExclusive = (task) => task(),
  storage,
  transport,
}: {
  isOnline?: () => boolean;
  ownerId: string;
  runExclusive?: <T>(task: () => Promise<T>) => Promise<T>;
  storage: QueueStorage;
  transport: InboxSyncTransport;
}): InboxSyncStore {
  let snapshot = serverSnapshot;
  let entries: QueuedInboxEntry[] = [];
  let isLoaded = false;
  let syncingId: string | null = null;
  let inFlight: Promise<void> | null = null;
  let rerunRequested = false;
  const firstAttemptIds = new Set<string>();
  const listeners = new Set<() => void>();
  const runListeners = new Set<(run: InboxSyncRun) => void>();

  function publish(changes: Partial<InboxSyncSnapshot>) {
    snapshot = { ...snapshot, ...changes };
    for (const listener of listeners) listener();
  }

  function itemsFor(queue: QueuedInboxEntry[]): PendingCapture[] {
    return queue.map((entry) => ({
      entry,
      firstAttempt: firstAttemptIds.has(entry.id),
      status: entry.id === syncingId ? "syncing" : "waiting",
    }));
  }

  function replaceEntries(queue: QueuedInboxEntry[]) {
    const ids = new Set(queue.map((entry) => entry.id));
    for (const id of firstAttemptIds)
      if (!ids.has(id)) firstAttemptIds.delete(id);
    entries = queue;
    isLoaded = true;
    publish({ isReady: true, items: itemsFor(queue) });
  }

  function readQueue() {
    return loadInboxQueue(storage, ownerId);
  }

  function ensureLoaded() {
    if (isLoaded) return;
    isLoaded = true;
    entries = readQueue();
    snapshot = { ...snapshot, isReady: true, items: itemsFor(entries) };
  }

  async function attempt(entry: QueuedInboxEntry): Promise<InboxSyncResult> {
    let result: InboxSyncResult;
    try {
      result = await transport.syncEntry(entry);
    } catch {
      result = { message: offlineSyncMessage, status: "retry" };
    }

    if (result.status === "retry" || entry.attachments.length === 0)
      return result;

    try {
      return await transport.syncAttachments(entry, (progress) =>
        publish({ photoUploadProgress: progress }),
      );
    } catch {
      return { message: offlinePhotoSyncMessage, status: "retry" };
    }
  }

  async function runOnce(): Promise<InboxSyncRun> {
    let result: InboxSyncResult | null = null;
    let synced = 0;
    const attempted = new Set<string>();
    let considered: QueuedInboxEntry[] = [];

    try {
      for (;;) {
        // Another tab may have synced or queued captures since the last step.
        considered = readQueue();
        const entry = considered.find(({ id }) => !attempted.has(id));
        if (!entry) break;

        attempted.add(entry.id);
        syncingId = entry.id;
        replaceEntries(considered);
        result = await attempt(entry);
        if (result.status === "retry") break;

        const nextQueue = removeInboxQueueEntry(storage, ownerId, entry.id);
        if (nextQueue === null) {
          result = { message: uncleanedQueueMessage, status: "retry" };
          break;
        }

        synced += 1;
        syncingId = null;
        replaceEntries(nextQueue);
        if (entry.attachments.length > 0)
          void transport.finishCapture(entry.id).catch(() => undefined);
      }
    } finally {
      syncingId = null;
      // Every capture this run could reach has had its first attempt; one
      // queued after the final read keeps it for the rerun it requested.
      for (const { id } of considered) firstAttemptIds.delete(id);
      replaceEntries(readQueue());
      publish({
        lastError: result?.status === "retry" ? result.message : null,
        photoUploadProgress: null,
        runCount: snapshot.runCount + 1,
      });
    }

    return { result, synced };
  }

  async function runUntilSettled() {
    publish({ isSyncing: true });
    try {
      do {
        rerunRequested = false;
        let run: InboxSyncRun;
        try {
          run = await runExclusive(runOnce);
        } catch {
          run = {
            result: { message: offlineSyncMessage, status: "retry" },
            synced: 0,
          };
          publish({
            lastError: offlineSyncMessage,
            runCount: snapshot.runCount + 1,
          });
        }
        for (const listener of runListeners) listener(run);
      } while (rerunRequested && readQueue().length > 0);
    } finally {
      inFlight = null;
      publish({ isSyncing: false, photoUploadProgress: null });
    }
  }

  function synchronize() {
    if (inFlight) {
      // A capture or reconnection arrived mid-run; settle it in one more run.
      rerunRequested = true;
      return inFlight;
    }

    ensureLoaded();
    const queue = readQueue();
    if (queue.length === 0) {
      if (entries.length > 0 || snapshot.lastError) {
        replaceEntries(queue);
        publish({ lastError: null });
      }
      return Promise.resolve();
    }

    inFlight = runUntilSettled();
    return inFlight;
  }

  return {
    enqueue(entry) {
      ensureLoaded();
      const nextQueue = enqueueInboxEntry(storage, ownerId, entry);
      if (!nextQueue) return null;
      if (isOnline() && !entries.some(({ id }) => id === entry.id))
        firstAttemptIds.add(entry.id);
      replaceEntries(nextQueue);
      void synchronize();
      return nextQueue;
    },
    getServerSnapshot: () => serverSnapshot,
    getSnapshot() {
      ensureLoaded();
      return snapshot;
    },
    onRunFinished(listener) {
      runListeners.add(listener);
      return () => runListeners.delete(listener);
    },
    reload() {
      const queue = readQueue();
      const remaining = new Set(queue.map(({ id }) => id));
      const removed = entries.filter(({ id }) => !remaining.has(id)).length;
      replaceEntries(queue);
      return removed;
    },
    subscribe(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    synchronize,
  };
}

/** Whether a pending list should appear; a first online attempt is progress. */
export function hasWaitingCaptures(snapshot: InboxSyncSnapshot) {
  return snapshot.items.some((item) => !item.firstAttempt);
}
