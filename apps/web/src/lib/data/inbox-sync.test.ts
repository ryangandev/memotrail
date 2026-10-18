import { describe, expect, it, vi } from "vitest";
import {
  enqueueInboxEntry,
  inboxQueueKey,
  loadInboxQueue,
  type QueuedInboxEntry,
} from "./inbox-queue";
import {
  countSyncedInQueueChange,
  createInboxSyncStore,
  hasWaitingCaptures,
  offlineSyncMessage,
  type InboxSyncResult,
  type InboxSyncRun,
  type InboxSyncTransport,
} from "./inbox-sync";

const ownerId = "owner-a";
const synced: InboxSyncResult = {
  message: "Saved to Library.",
  status: "synced",
};
const rejected: InboxSyncResult = {
  message: "MemoTrail cannot accept this Entry, so it will not sync.",
  status: "rejected",
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
    expect(runs).toEqual([{ rejected: 0, result: synced, synced: 1 }]);
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
      {
        rejected: 0,
        result: { message: offlineSyncMessage, status: "retry" },
        synced: 0,
      },
      { rejected: 0, result: synced, synced: 2 },
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
      {
        rejected: 0,
        result: { message: offlineSyncMessage, status: "retry" },
        synced: 0,
      },
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
      return { message: "Saved to Library with 1 photo.", status: "synced" };
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
    store.reload();
    expect(store.getSnapshot().items).toHaveLength(1);
    lock.resolve();
    await running;

    expect(lockRequests).toBe(1);
    expect(transport.syncEntry.mock.calls.map(([entry]) => entry.id)).toEqual([
      queuedEntry(2).id,
    ]);
    enqueueInboxEntry(storage, ownerId, queuedEntry(3));
    store.reload();
    expect(store.getSnapshot().items).toHaveLength(1);
  });

  it("counts what another tab synced from its change, however late this tab hears of it", () => {
    const queue = (...entries: QueuedInboxEntry[]) => JSON.stringify(entries);
    // This tab may have reread the queue in its own run before the change
    // arrives, so the count comes from the change, not from this tab's list.
    expect(
      countSyncedInQueueChange(
        queue(queuedEntry(1), queuedEntry(2)),
        queue(queuedEntry(2)),
      ),
    ).toBe(1);
    expect(countSyncedInQueueChange(queue(queuedEntry(1)), null)).toBe(1);
    // A capture another tab queued is new here, not synced.
    expect(
      countSyncedInQueueChange(
        queue(queuedEntry(2)),
        queue(queuedEntry(2), queuedEntry(3)),
      ),
    ).toBe(0);
    expect(countSyncedInQueueChange(null, null)).toBe(0);
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

  it("keeps a rejected capture with its content and syncs the captures after it", async () => {
    const { runs, storage, store, transport } = setup();
    transport.syncEntry.mockResolvedValueOnce(rejected);
    enqueueInboxEntry(storage, ownerId, queuedEntry(1));
    enqueueInboxEntry(storage, ownerId, queuedEntry(2));
    await store.synchronize();

    expect(transport.syncEntry.mock.calls.map(([entry]) => entry.id)).toEqual([
      queuedEntry(1).id,
      queuedEntry(2).id,
    ]);
    const rejection = {
      message: rejected.message,
      rejectedAt: expect.any(String),
    };
    expect(loadInboxQueue(storage, ownerId)).toEqual([
      { ...queuedEntry(1), rejection },
    ]);
    expect(store.getSnapshot()).toMatchObject({
      isSyncing: false,
      items: [
        {
          entry: { id: queuedEntry(1).id },
          firstAttempt: false,
          rejection,
          status: "rejected",
        },
      ],
      // A rejection is the capture's own problem, not one that ended the run.
      lastError: null,
    });
    expect(hasWaitingCaptures(store.getSnapshot())).toBe(true);
    expect(runs).toEqual([{ rejected: 1, result: synced, synced: 1 }]);
  });

  it("never sends a rejected capture again, even after a reload", async () => {
    const storage = memoryStorage();
    const first = setup({ storage });
    first.transport.syncEntry.mockResolvedValueOnce(rejected);
    first.store.enqueue(queuedEntry(1));
    await first.store.synchronize();
    await first.store.synchronize();
    expect(first.transport.syncEntry).toHaveBeenCalledTimes(1);

    const { runs, store, transport } = setup({ storage });
    expect(store.getSnapshot().items).toMatchObject([
      { rejection: { message: rejected.message }, status: "rejected" },
    ]);
    await store.synchronize();
    expect(transport.syncEntry).not.toHaveBeenCalled();
    expect(runs).toEqual([]);

    store.enqueue(queuedEntry(2));
    await store.synchronize();
    expect(transport.syncEntry.mock.calls.map(([entry]) => entry.id)).toEqual([
      queuedEntry(2).id,
    ]);
    expect(store.getSnapshot().items).toMatchObject([
      { entry: { id: queuedEntry(1).id }, status: "rejected" },
    ]);
  });

  it("still stops at a retryable failure after a rejected capture", async () => {
    const { runs, storage, store, transport } = setup();
    transport.syncEntry
      .mockResolvedValueOnce(rejected)
      .mockResolvedValueOnce({ message: offlineSyncMessage, status: "retry" });
    for (const index of [1, 2, 3])
      enqueueInboxEntry(storage, ownerId, queuedEntry(index));
    await store.synchronize();

    expect(transport.syncEntry).toHaveBeenCalledTimes(2);
    expect(store.getSnapshot()).toMatchObject({
      items: [
        { status: "rejected" },
        { status: "waiting" },
        { status: "waiting" },
      ],
      lastError: offlineSyncMessage,
    });
    expect(runs).toEqual([
      {
        rejected: 1,
        result: { message: offlineSyncMessage, status: "retry" },
        synced: 0,
      },
    ]);
  });

  it("rejects a capture whose photos MemoTrail refuses, without finishing it", async () => {
    const { storage, store, transport } = setup();
    transport.syncAttachments.mockResolvedValueOnce(rejected);
    enqueueInboxEntry(storage, ownerId, queuedEntry(1, { withPhoto: true }));
    enqueueInboxEntry(storage, ownerId, queuedEntry(2));
    await store.synchronize();

    expect(transport.finishCapture).not.toHaveBeenCalled();
    expect(store.getSnapshot()).toMatchObject({
      items: [{ entry: { id: queuedEntry(1).id }, status: "rejected" }],
      photoUploadProgress: null,
    });
  });

  it("keeps a rejected capture waiting when this browser cannot record the rejection", async () => {
    const { storage, store, transport } = setup();
    transport.syncEntry.mockResolvedValueOnce(rejected);
    enqueueInboxEntry(storage, ownerId, queuedEntry(1));
    enqueueInboxEntry(storage, ownerId, queuedEntry(2));
    storage.setItem.mockImplementationOnce(() => {
      throw new Error("quota");
    });
    await store.synchronize();

    expect(transport.syncEntry).toHaveBeenCalledTimes(1);
    expect(store.getSnapshot()).toMatchObject({
      items: [{ status: "waiting" }, { status: "waiting" }],
      lastError: rejected.message,
    });
  });

  it("discards a rejected capture and its photos, photos first", async () => {
    const { removePhotoDrafts, storage, store, transport } = setup();
    transport.syncEntry.mockResolvedValueOnce(rejected);
    store.enqueue(queuedEntry(1, { withPhoto: true }));
    await store.synchronize();
    removePhotoDrafts.mockImplementationOnce(async () => {
      // The capture is still stored while its photos are removed.
      expect(loadInboxQueue(storage, ownerId)).toHaveLength(1);
    });

    await expect(store.discard(queuedEntry(1).id)).resolves.toBe(true);
    expect(removePhotoDrafts).toHaveBeenCalledWith([
      queuedEntry(1, { withPhoto: true }).attachments[0].id,
    ]);
    expect(loadInboxQueue(storage, ownerId)).toEqual([]);
    expect(store.getSnapshot().items).toEqual([]);
    expect(hasWaitingCaptures(store.getSnapshot())).toBe(false);
  });

  it("keeps a rejected capture whose photos could not be discarded", async () => {
    const { removePhotoDrafts, storage, store, transport } = setup();
    transport.syncEntry.mockResolvedValueOnce(rejected);
    store.enqueue(queuedEntry(1, { withPhoto: true }));
    await store.synchronize();
    removePhotoDrafts.mockRejectedValueOnce(new Error("blocked"));

    await expect(store.discard(queuedEntry(1).id)).resolves.toBe(false);
    expect(loadInboxQueue(storage, ownerId)).toHaveLength(1);
    expect(store.getSnapshot().items).toMatchObject([{ status: "rejected" }]);
  });

  it("never discards a capture that is still waiting to sync", async () => {
    const { removePhotoDrafts, storage, store } = setup();
    enqueueInboxEntry(storage, ownerId, queuedEntry(1, { withPhoto: true }));

    await expect(store.discard(queuedEntry(1).id)).resolves.toBe(false);
    expect(removePhotoDrafts).not.toHaveBeenCalled();
    expect(loadInboxQueue(storage, ownerId)).toHaveLength(1);
  });

  it("does not count a capture another tab discarded as synced", async () => {
    const storage = memoryStorage();
    const { store, transport } = setup({ storage });
    transport.syncEntry.mockResolvedValueOnce(rejected);
    store.enqueue(queuedEntry(1));
    await store.synchronize();

    const other = setup({ storage });
    const before = storage.getItem(inboxQueueKey(ownerId));
    await other.store.discard(queuedEntry(1).id);
    expect(
      countSyncedInQueueChange(before, storage.getItem(inboxQueueKey(ownerId))),
    ).toBe(0);
    store.reload();
    expect(store.getSnapshot().items).toEqual([]);
  });

  it("lists an unreadable capture, keeps it through a sync, and discards it on request", async () => {
    const storage = memoryStorage();
    const unreadable = {
      ...queuedEntry(2, { withPhoto: true }),
      body: "Written offline before a rule changed.",
      occurredAt: "not a date",
    };
    storage.setItem(
      inboxQueueKey(ownerId),
      JSON.stringify([unreadable, queuedEntry(1)]),
    );
    const { removePhotoDrafts, store, transport } = setup({ storage });

    expect(store.getSnapshot().unreadable).toMatchObject([
      { text: "Written offline before a rule changed." },
    ]);
    expect(hasWaitingCaptures(store.getSnapshot())).toBe(true);
    await store.synchronize();

    // The valid capture synced; the unreadable one is still on this device.
    expect(transport.syncEntry).toHaveBeenCalledTimes(1);
    expect(store.getSnapshot().items).toEqual([]);
    const [{ key }] = store.getSnapshot().unreadable;
    expect(key).toContain("Written offline before a rule changed.");
    expect(hasWaitingCaptures(store.getSnapshot())).toBe(true);

    await expect(store.discardUnreadable(key)).resolves.toBe(true);
    expect(removePhotoDrafts).toHaveBeenCalledWith([
      queuedEntry(2, { withPhoto: true }).attachments[0].id,
    ]);
    expect(store.getSnapshot().unreadable).toEqual([]);
    expect(hasWaitingCaptures(store.getSnapshot())).toBe(false);
  });

  it("keeps an unreadable capture whose photos could not be removed", async () => {
    const storage = memoryStorage();
    storage.setItem(inboxQueueKey(ownerId), JSON.stringify([{ id: 7 }]));
    const { removePhotoDrafts, store } = setup({ storage });
    const [{ key }] = store.getSnapshot().unreadable;
    removePhotoDrafts.mockRejectedValueOnce(new Error("blocked"));

    await expect(store.discardUnreadable(key)).resolves.toBe(false);
    expect(store.getSnapshot().unreadable).toHaveLength(1);
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
  const removePhotoDrafts = vi.fn(async (attachmentIds: string[]) => {
    void attachmentIds;
  });
  const store = createInboxSyncStore({
    isOnline: () => isOnline,
    ownerId,
    removePhotoDrafts,
    runExclusive,
    storage,
    transport,
  });
  const runs: InboxSyncRun[] = [];
  store.onRunFinished((run) => runs.push(run));
  return { removePhotoDrafts, runs, storage, store, transport };
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
