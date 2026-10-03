"use client";

import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useSyncExternalStore,
  type ReactNode,
} from "react";
import { useRouter } from "next/navigation";
import {
  finishInboxCapture,
  registerEntryAttachment,
  syncInboxEntry,
} from "@/app/inbox/actions";
import { notify } from "@/components/app-toast";
import { countLabel } from "@/lib/count-label";
import {
  createFirstTimeObjectPath,
  type FirstTimeAttachmentInput,
} from "@/lib/data/first-time-input";
import {
  loadInboxPhotoDrafts,
  removeInboxPhotoDrafts,
} from "@/lib/data/inbox-photo-store";
import {
  inboxQueueKey,
  type QueueStorage,
  type QueuedInboxEntry,
} from "@/lib/data/inbox-queue";
import {
  createInboxSyncStore,
  type InboxSyncResult,
  type InboxSyncSnapshot,
  type InboxSyncStore,
} from "@/lib/data/inbox-sync";
import type { PhotoUploadProgress } from "@/lib/media/upload";
import { createClient } from "@/lib/supabase/client";

const CaptureContext = createContext<InboxSyncStore | null>(null);

// One store per person per tab, however many shells or composers mount.
const stores = new Map<string, InboxSyncStore>();

/**
 * Owns the signed-in person's pending captures for the whole workspace, so
 * they sync on load, on reconnection, and when queued, from any page.
 */
export function CaptureProvider({
  children,
  ownerId,
}: {
  children: ReactNode;
  ownerId: string;
}) {
  const router = useRouter();
  const store = useMemo(() => inboxSyncStoreFor(ownerId), [ownerId]);

  useEffect(() => {
    const stopWatchingRuns = store.onRunFinished(({ result, synced }) => {
      if (result?.status === "synced") notify.success(result.message);
      if (synced > 0) router.refresh();
    });
    function handleOnline() {
      void store.synchronize();
    }
    function handleStorage(event: StorageEvent) {
      if (event.key !== null && event.key !== inboxQueueKey(ownerId)) return;
      // Another tab synced captures, so this page's Inbox counts are stale.
      if (store.reload() > 0) router.refresh();
    }

    window.addEventListener("online", handleOnline);
    window.addEventListener("storage", handleStorage);
    if (navigator.onLine) void store.synchronize();

    return () => {
      stopWatchingRuns();
      window.removeEventListener("online", handleOnline);
      window.removeEventListener("storage", handleStorage);
    };
  }, [ownerId, router, store]);

  return <CaptureContext value={store}>{children}</CaptureContext>;
}

export type CaptureQueue = InboxSyncSnapshot &
  Pick<InboxSyncStore, "enqueue" | "getSnapshot" | "synchronize">;

/**
 * The workspace's pending captures and the actions that change them.
 * `getSnapshot` reads the current queue outside rendering, such as in an effect.
 */
export function useCaptureQueue(): CaptureQueue {
  const store = useContext(CaptureContext);
  if (!store)
    throw new Error("useCaptureQueue must be used inside CaptureProvider.");
  const snapshot = useSyncExternalStore(
    store.subscribe,
    store.getSnapshot,
    store.getServerSnapshot,
  );
  return {
    ...snapshot,
    enqueue: store.enqueue,
    getSnapshot: store.getSnapshot,
    synchronize: store.synchronize,
  };
}

function inboxSyncStoreFor(ownerId: string) {
  const existing = typeof window === "undefined" ? null : stores.get(ownerId);
  if (existing) return existing;

  const lockName = `memotrail:inbox-sync:${encodeURIComponent(ownerId)}`;
  const store = createInboxSyncStore({
    isOnline: () => navigator.onLine,
    ownerId,
    runExclusive: (task) => runAcrossTabs(lockName, task),
    storage: browserQueueStorage,
    transport: {
      finishCapture: finishInboxCapture,
      syncAttachments: (entry, onProgress) =>
        synchronizeAttachments(ownerId, entry, onProgress),
      syncEntry: (entry) => {
        const { bodyRich, ...syncInput } = entry;
        return syncInboxEntry(
          syncInput,
          bodyRich ? JSON.stringify(bodyRich) : null,
        );
      },
    },
  });
  // Only a browser tab keeps its store; a server render reads nothing from it.
  if (typeof window !== "undefined") stores.set(ownerId, store);
  return store;
}

// Resolved on use, so a blocked browser storage API reaches the queue's own
// error handling instead of failing while the workspace renders.
const browserQueueStorage: QueueStorage = {
  getItem: (key) => window.localStorage.getItem(key),
  removeItem: (key) => window.localStorage.removeItem(key),
  setItem: (key, value) => window.localStorage.setItem(key, value),
};

/**
 * Tabs share one localStorage queue, so a Web Lock lets only one of them send
 * it at a time; the next tab rereads the queue and skips what already synced.
 */
async function runAcrossTabs<T>(name: string, task: () => Promise<T>) {
  const locks = typeof navigator === "undefined" ? undefined : navigator.locks;
  if (!locks) return task();

  let started = false;
  try {
    return await locks.request(name, () => {
      started = true;
      return task();
    });
  } catch (error) {
    if (started) throw error;
    // An unavailable lock manager should not strand captures in this tab.
    return task();
  }
}

async function synchronizeAttachments(
  ownerId: string,
  entry: QueuedInboxEntry,
  onProgress?: (progress: PhotoUploadProgress) => void,
): Promise<InboxSyncResult> {
  const storedPhotos = await loadInboxPhotoDrafts(ownerId);
  const photosById = new Map(storedPhotos.map((photo) => [photo.id, photo]));
  const client = createClient();

  let completed = 0;
  onProgress?.({ completed, total: entry.attachments.length });
  for (const attachment of entry.attachments) {
    const photo = photosById.get(attachment.id);
    const objectPath = createFirstTimeObjectPath(
      ownerId,
      entry.id,
      attachment.id,
      attachment.mimeType,
    );

    if (!objectPath) {
      return {
        message:
          "A pending photo reference is invalid and needs your attention.",
        status: "retry",
      };
    }

    const attachmentInput: FirstTimeAttachmentInput = {
      attachmentId: attachment.id,
      byteSize: attachment.size,
      entryId: entry.id,
      mimeType: attachment.mimeType,
      objectPath,
      originalFilename: attachment.name || null,
      pixelHeight: null,
      pixelWidth: null,
    };

    if (!photo) {
      const registered = await registerEntryAttachment(attachmentInput);

      if (registered.status === "synced") {
        continue;
      }

      return {
        message:
          "A pending photo is missing from this device. Keep this page open and select the photo again if needed.",
        status: "retry",
      };
    }

    if (
      photo.file.name !== attachment.name ||
      photo.file.size !== attachment.size ||
      photo.file.lastModified !== attachment.lastModified ||
      photo.mimeType !== attachment.mimeType
    ) {
      return {
        message: "A pending photo changed on this device and cannot be synced.",
        status: "retry",
      };
    }

    await client.storage.from("entry-media").upload(objectPath, photo.file, {
      cacheControl: "3600",
      contentType: attachment.mimeType,
      upsert: false,
    });

    const registered = await registerEntryAttachment(attachmentInput);

    if (registered.status === "retry") {
      return registered;
    }

    try {
      await removeInboxPhotoDrafts(ownerId, [attachment.id]);
    } catch {
      return {
        message:
          "This photo reached MemoTrail, but its local pending copy could not be cleared. Retry to finish.",
        status: "retry",
      };
    }
    completed += 1;
    onProgress?.({ completed, total: entry.attachments.length });
  }

  return {
    message: `Saved to Inbox with ${countLabel(entry.attachments.length, "photo")}.`,
    status: "synced",
  };
}
