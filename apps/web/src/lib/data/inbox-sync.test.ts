import { describe, expect, it, vi } from "vitest";
import {
  enqueueInboxEntry,
  inboxQueueKey,
  loadInboxQueue,
  type QueuedInboxEntry,
} from "./inbox-queue";
import {
  createInboxSyncStore,
  hasWaitingCaptures,
  offlineSyncMessage,
  type InboxSyncResult,
  type InboxSyncRun,
  type InboxSyncTransport,
} from "./inbox-sync";

const ownerId = "owner-a";
const synced: InboxSyncResult = {
  message: "Saved to Inbox.",
  status: "synced",
};

describe("Workspace capture synchronization", () => {
  it("reads the browser queue lazily and keeps server rendering empty", () => {
    const storage = memoryStorage();
    enqueueInboxEntry(storage, ownerId, queuedEntry(1));
    storage.getItem.mockClear();
    const { store } = setup({ storage });

    expect(storage.getItem).not.toHaveBeenCalled();
    expect(store.getServerSnapshot()).toMatchObject({
      isReady: false,
      items: [],
    });
    expect(store.getSnapshot()).toMatchObject({
      isReady: true,
      items: [
        { entry: queuedEntry(1), firstAttempt: false, status: "waiting" },
      ],
    });
    expect(store.getSnapshot()).toBe(store.getSnapshot());
    expect(hasWaitingCaptures(store.getSnapshot())).toBe(true);
  });

  it("syncs a queued capture as soon as it is stored, then reports the run", async () => {
    const { runs, storage, store, transport } = setup();

    expect(store.enqueue(queuedEntry(1))).toEqual([queuedEntry(1)]);
    // An online save's first attempt is progress, not a Pending sync list.
    expect(store.getSnapshot()).toMatchObject({
      isSyncing: true,
      items: [{ firstAttempt: true }],
    });
    expect(hasWaitingCaptures(store.getSnapshot())).toBe(false);
    await store.synchronize();

    expect(transport.syncEntry).toHaveBeenCalledTimes(1);
    expect(loadInboxQueue(storage, ownerId)).toEqual([]);
    expect(store.getSnapshot()).toMatchObject({
      isSyncing: false,
      items: [],
      lastError: null,
      runCount: 1,
    });
    expect(runs).toEqual([{ result: synced, synced: 1 }]);
  });

  it("lists a capture saved offline immediately", () => {
    const { store, transport } = setup({ isOnline: false });
    transport.syncEntry.mockImplementation(() => new Promise(() => undefined));

    store.enqueue(queuedEntry(1));

    expect(store.getSnapshot().items).toMatchObject([{ firstAttempt: false }]);
    expect(hasWaitingCaptures(store.getSnapshot())).toBe(true);
  });

  it("sends each capture once when several triggers overlap", async () => {
    const { storage, store, transport } = setup();
    const first = deferred<InboxSyncResult>();
    transport.syncEntry.mockImplementationOnce(() => first.promise);
    enqueueInboxEntry(storage, ownerId, queuedEntry(1));

    const running = store.synchronize();
    // A reconnection, a composer, and the header indicator all ask at once.
    expect(store.synchronize()).toBe(running);
    expect(store.synchronize()).toBe(running);
    store.enqueue(queuedEntry(2));
    expect(store.getSnapshot().items).toMatchObject([
      { entry: { id: queuedEntry(1).id }, status: "syncing" },
      { entry: { id: queuedEntry(2).id }, status: "waiting" },
    ]);
    first.resolve(synced);
    await running;

    expect(transport.syncEntry.mock.calls.map(([entry]) => entry.id)).toEqual([
      queuedEntry(1).id,
      queuedEntry(2).id,
    ]);
    expect(loadInboxQueue(storage, ownerId)).toEqual([]);
  });

  it("stops at the first capture that must wait and keeps the rest in order", async () => {
    const { runs, storage, store, transport } = setup();
    const first = deferred<InboxSyncResult>();
    transport.syncEntry.mockImplementationOnce(() => first.promise);
    enqueueInboxEntry(storage, ownerId, queuedEntry(1));

    const running = store.synchronize();
    store.enqueue(queuedEntry(2));
    expect(store.getSnapshot().items[1]).toMatchObject({ firstAttempt: true });
    first.resolve({ message: offlineSyncMessage, status: "retry" });
    await running;

    // The capture queued mid-run asked for one more run, which starts again
    // from the oldest capture instead of skipping past it.
    expect(transport.syncEntry.mock.calls.map(([entry]) => entry.id)).toEqual([
      queuedEntry(1).id,
      queuedEntry(1).id,
      queuedEntry(2).id,
    ]);
    expect(store.getSnapshot()).toMatchObject({
      isSyncing: false,
      items: [],
      lastError: null,
      runCount: 2,
    });
    expect(runs).toEqual([
      { result: { message: offlineSyncMessage, status: "retry" }, synced: 0 },
      { result: synced, synced: 2 },
    ]);
  });

  it("keeps waiting captures and the run's problem after a failed attempt", async () => {
    const { runs, storage, store, transport } = setup();
    transport.syncEntry.mockResolvedValueOnce({
      message: offlineSyncMessage,
      status: "retry",
    });
    enqueueInboxEntry(storage, ownerId, queuedEntry(1));
    enqueueInboxEntry(storage, ownerId, queuedEntry(2));
    await store.synchronize();

    expect(transport.syncEntry).toHaveBeenCalledTimes(1);
    expect(store.getSnapshot()).toMatchObject({
      isSyncing: false,
      items: [
        { firstAttempt: false, status: "waiting" },
        { firstAttempt: false, status: "waiting" },
      ],
      lastError: offlineSyncMessage,
    });
    expect(runs).toEqual([
      { result: { message: offlineSyncMessage, status: "retry" }, synced: 0 },
    ]);

    await store.synchronize();
    expect(transport.syncEntry).toHaveBeenCalledTimes(3);
    expect(store.getSnapshot()).toMatchObject({ items: [], lastError: null });
  });

  it("treats an unreachable server action as a retry and never rejects", async () => {
    const { storage, store, transport } = setup();
    transport.syncEntry.mockRejectedValueOnce(new TypeError("Failed to fetch"));
    enqueueInboxEntry(storage, ownerId, queuedEntry(1));

    await expect(store.synchronize()).resolves.toBeUndefined();
    expect(store.getSnapshot().lastError).toBe(offlineSyncMessage);
    expect(loadInboxQueue(storage, ownerId)).toHaveLength(1);
  });

  it("finishes a capture with photos after its upload and clears progress", async () => {
    const { storage, store, transport } = setup();
    const progress: unknown[] = [];
    transport.syncAttachments.mockImplementationOnce(async (_, onProgress) => {
      onProgress({ completed: 0, total: 1 });
      progress.push(store.getSnapshot().photoUploadProgress);
      onProgress({ completed: 1, total: 1 });
      return { message: "Saved to Inbox with 1 photo.", status: "synced" };
    });
    enqueueInboxEntry(storage, ownerId, queuedEntry(1, { withPhoto: true }));
    await store.synchronize();

    expect(progress).toEqual([{ completed: 0, total: 1 }]);
    expect(transport.finishCapture).toHaveBeenCalledWith(queuedEntry(1).id);
    expect(store.getSnapshot()).toMatchObject({
      items: [],
      photoUploadProgress: null,
    });
  });

  it("keeps a capture whose photos could not sync", async () => {
    const { storage, store, transport } = setup();
    transport.syncAttachments.mockRejectedValueOnce(new Error("offline"));
    enqueueInboxEntry(storage, ownerId, queuedEntry(1, { withPhoto: true }));
    await store.synchronize();

    expect(transport.finishCapture).not.toHaveBeenCalled();
    expect(loadInboxQueue(storage, ownerId)).toHaveLength(1);
    expect(store.getSnapshot().lastError).toBe(
      "Photos are saved on this device. MemoTrail will retry when you are online.",
    );
  });

  it("reports a synced capture whose local copy could not be cleared", async () => {
    const { storage, store } = setup();
    enqueueInboxEntry(storage, ownerId, queuedEntry(1));
    storage.removeItem.mockImplementationOnce(() => {
      throw new Error("blocked");
    });
    await store.synchronize();

    expect(store.getSnapshot().lastError).toBe(
      "This Entry reached MemoTrail, but its local pending copy could not be cleared.",
    );
  });

  it("serializes runs through the cross-tab lock and skips what another tab synced", async () => {
    const storage = memoryStorage();
    const lock = deferred<void>();
    let lockRequests = 0;
    const runExclusive = async <T>(task: () => Promise<T>) => {
      lockRequests += 1;
      await lock.promise;
      return task();
    };
    const { store, transport } = setup({ runExclusive, storage });
    enqueueInboxEntry(storage, ownerId, queuedEntry(1));
    enqueueInboxEntry(storage, ownerId, queuedEntry(2));

    const running = store.synchronize();
    expect(store.getSnapshot().isSyncing).toBe(true);
    // The tab holding the lock sends the first capture meanwhile.
    storage.setItem(inboxQueueKey(ownerId), JSON.stringify([queuedEntry(2)]));
    expect(store.reload()).toBe(1);
    expect(store.getSnapshot().items).toHaveLength(1);
    lock.resolve();
    await running;

    expect(lockRequests).toBe(1);
    expect(transport.syncEntry.mock.calls.map(([entry]) => entry.id)).toEqual([
      queuedEntry(2).id,
    ]);
    // A capture another tab queued is new here, not synced.
    enqueueInboxEntry(storage, ownerId, queuedEntry(3));
    expect(store.reload()).toBe(0);
    expect(store.getSnapshot().items).toHaveLength(1);
  });

  it("does not run, toast, or refresh when nothing is waiting", async () => {
    const { runs, store, transport } = setup();

    await store.synchronize();

    expect(transport.syncEntry).not.toHaveBeenCalled();
    expect(store.getSnapshot()).toMatchObject({
      isSyncing: false,
      runCount: 0,
    });
    expect(runs).toEqual([]);
  });

  it("refuses a capture this browser cannot store", () => {
    const { storage, store, transport } = setup();
    storage.setItem.mockImplementationOnce(() => {
      throw new Error("quota");
    });

    expect(store.enqueue(queuedEntry(1))).toBeNull();
    expect(store.getSnapshot().items).toEqual([]);
    expect(transport.syncEntry).not.toHaveBeenCalled();
  });
});

function setup({
  isOnline = true,
  runExclusive,
  storage = memoryStorage(),
}: {
  isOnline?: boolean;
  runExclusive?: <T>(task: () => Promise<T>) => Promise<T>;
  storage?: ReturnType<typeof memoryStorage>;
} = {}) {
  const transport = {
    finishCapture: vi.fn<InboxSyncTransport["finishCapture"]>(
      async () => undefined,
    ),
    syncAttachments: vi.fn<InboxSyncTransport["syncAttachments"]>(
      async () => synced,
    ),
    syncEntry: vi.fn<InboxSyncTransport["syncEntry"]>(async () => synced),
  };
  const store = createInboxSyncStore({
    isOnline: () => isOnline,
    ownerId,
    runExclusive,
    storage,
    transport,
  });
  const runs: InboxSyncRun[] = [];
  store.onRunFinished((run) => runs.push(run));
  return { runs, storage, store, transport };
}

function queuedEntry(
  index: number,
  { withPhoto = false }: { withPhoto?: boolean } = {},
): QueuedInboxEntry {
  return {
    attachments: withPhoto
      ? [
          {
            id: `00000000-0000-4000-8000-00000000010${index}`,
            lastModified: 1,
            mimeType: "image/jpeg",
            name: "memory.jpg",
            size: 10,
          },
        ]
      : [],
    body: `Capture ${index}`,
    id: `00000000-0000-4000-8000-00000000000${index}`,
    occurredAt: "2026-10-03T12:00:00.000Z",
    occurredTimezone: "UTC",
    queuedAt: "2026-10-03T12:00:00.000Z",
    title: null,
    version: 2,
  };
}

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((settle) => {
    resolve = settle;
  });
  return { promise, resolve };
}

function memoryStorage() {
  const values = new Map<string, string>();

  return {
    getItem: vi.fn((key: string) => values.get(key) ?? null),
    removeItem: vi.fn((key: string) => {
      values.delete(key);
    }),
    setItem: vi.fn((key: string, value: string) => {
      values.set(key, value);
    }),
  };
}
