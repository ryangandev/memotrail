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
import { inboxDraftKey } from "@/lib/data/inbox-draft";
import {
  createInboxDraftStore,
  type InboxDraftSnapshot,
  type InboxDraftStore,
} from "@/lib/data/inbox-draft-store";
import {
  loadInboxPhotoDrafts,
  persistInboxPhotoDrafts,
  removeInboxPhotoDrafts,
} from "@/lib/data/inbox-photo-store";
import {
  inboxQueueKey,
  loadInboxQueue,
  type QueueStorage,
  type QueuedInboxEntry,
} from "@/lib/data/inbox-queue";
import {
  createInboxSyncStore,
  type InboxSyncResult,
  type InboxSyncSnapshot,
  type InboxSyncStore,
} from "@/lib/data/inbox-sync";
import { browserSpeechRecognitionConstructor } from "@/lib/data/voice-transcript";
import type { PhotoUploadProgress } from "@/lib/media/upload";
import { createClient } from "@/lib/supabase/client";

/** The capture being composed and the captures waiting to sync. */
type WorkspaceCapture = {
  draft: InboxDraftStore;
  queue: InboxSyncStore;
};

const CaptureContext = createContext<WorkspaceCapture | null>(null);

// One draft and one queue per person per tab, however many shells or
// composers mount.
const workspaces = new Map<string, WorkspaceCapture>();

/**
 * Owns the signed-in person's capture draft and pending captures for the
 * whole workspace. Every composer edits the same draft, which follows other
 * tabs, and pending captures sync on load, on reconnection, and when queued,
 * from any page.
 */
export function CaptureProvider({
  children,
  ownerId,
}: {
  children: ReactNode;
  ownerId: string;
}) {
  const router = useRouter();
  const capture = useMemo(() => workspaceCaptureFor(ownerId), [ownerId]);

  useEffect(() => {
    const { draft, queue } = capture;
    const stopWatchingRuns = queue.onRunFinished(
      ({ rejected, result, synced }) => {
        if (result?.status === "synced") notify.success(result.message);
        // A rejected capture may come from a composer that is already closed.
        if (rejected > 0)
          notify.error(
            `MemoTrail did not accept ${countLabel(rejected, "Entry")}. Review ${rejected === 1 ? "it" : "them"} in Pending sync.`,
          );
        if (synced > 0) router.refresh();
      },
    );
    function handleOnline() {
      void queue.synchronize();
    }
    function handleStorage(event: StorageEvent) {
      if (event.key === null || event.key === inboxDraftKey(ownerId))
        draft.reload();
      if (event.key !== null && event.key !== inboxQueueKey(ownerId)) return;
      // Another tab synced captures, so this page's Inbox counts are stale.
      if (queue.reload() > 0) router.refresh();
    }
    function handlePageShow(event: PageTransitionEvent) {
      // A page restored from the back-forward cache missed other tabs' edits.
      if (!event.persisted) return;
      draft.reload();
      void draft.reloadPhotos();
    }
    // Photo drafts live in IndexedDB, which tells other tabs nothing, so tabs
    // announce their photo changes to each other.
    const photoChannel =
      typeof BroadcastChannel === "undefined"
        ? null
        : new BroadcastChannel(
            `memotrail:inbox-draft-photos:${encodeURIComponent(ownerId)}`,
          );
    if (photoChannel)
      photoChannel.onmessage = () => {
        void draft.reloadPhotos();
      };
    const stopAnnouncingPhotos = draft.onPhotosChanged(() =>
      photoChannel?.postMessage("changed"),
    );

    window.addEventListener("online", handleOnline);
    window.addEventListener("pageshow", handlePageShow);
    window.addEventListener("storage", handleStorage);
    void draft.loadPhotos();
    if (navigator.onLine) void queue.synchronize();

    return () => {
      stopWatchingRuns();
      stopAnnouncingPhotos();
      photoChannel?.close();
      window.removeEventListener("online", handleOnline);
      window.removeEventListener("pageshow", handlePageShow);
      window.removeEventListener("storage", handleStorage);
    };
  }, [capture, ownerId, router]);

  return <CaptureContext value={capture}>{children}</CaptureContext>;
}

function useWorkspaceCapture(hook: string) {
  const capture = useContext(CaptureContext);
  if (!capture) throw new Error(`${hook} must be used inside CaptureProvider.`);
  return capture;
}

export type CaptureQueue = InboxSyncSnapshot &
  Pick<InboxSyncStore, "discard" | "enqueue" | "getSnapshot" | "synchronize">;

/**
 * The workspace's pending captures and the actions that change them.
 * `getSnapshot` reads the current queue outside rendering, such as in an effect.
 */
export function useCaptureQueue(): CaptureQueue {
  const { queue } = useWorkspaceCapture("useCaptureQueue");
  const snapshot = useSyncExternalStore(
    queue.subscribe,
    queue.getSnapshot,
    queue.getServerSnapshot,
  );
  return {
    ...snapshot,
    discard: queue.discard,
    enqueue: queue.enqueue,
    getSnapshot: queue.getSnapshot,
    synchronize: queue.synchronize,
  };
}

export type CaptureDraft = InboxDraftSnapshot &
  Pick<
    InboxDraftStore,
    | "addPhotos"
    | "cancelVoice"
    | "clear"
    | "getSnapshot"
    | "removePhoto"
    | "startVoice"
    | "stopVoice"
    | "update"
  >;

/**
 * The capture draft every composer in this tab shows and edits, and the
 * actions that change it. `getSnapshot` reads the latest draft after an await.
 */
export function useCaptureDraft(): CaptureDraft {
  const { draft } = useWorkspaceCapture("useCaptureDraft");
  const snapshot = useSyncExternalStore(
    draft.subscribe,
    draft.getSnapshot,
    draft.getServerSnapshot,
  );
  return {
    ...snapshot,
    addPhotos: draft.addPhotos,
    cancelVoice: draft.cancelVoice,
    clear: draft.clear,
    getSnapshot: draft.getSnapshot,
    removePhoto: draft.removePhoto,
    startVoice: draft.startVoice,
    stopVoice: draft.stopVoice,
    update: draft.update,
  };
}

function workspaceCaptureFor(ownerId: string): WorkspaceCapture {
  const existing =
    typeof window === "undefined" ? null : workspaces.get(ownerId);
  if (existing) return existing;

  const lockName = `memotrail:inbox-sync:${encodeURIComponent(ownerId)}`;
  const queue = createInboxSyncStore({
    isOnline: () => navigator.onLine,
    ownerId,
    removePhotoDrafts: (attachmentIds) =>
      removeInboxPhotoDrafts(ownerId, attachmentIds),
    runExclusive: (task) => runAcrossTabs(lockName, task),
    storage: browserStorage,
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
  const draft = createInboxDraftStore({
    language: () => navigator.language || "en-US",
    ownerId,
    photoStorage: {
      load: loadInboxPhotoDrafts,
      persist: persistInboxPhotoDrafts,
      remove: removeInboxPhotoDrafts,
    },
    // Read from storage, since another tab may have queued photos just now.
    queuedPhotoIds: () =>
      new Set(
        loadInboxQueue(browserStorage, ownerId).flatMap((entry) =>
          entry.attachments.map(({ id }) => id),
        ),
      ),
    speechRecognition: () => browserSpeechRecognitionConstructor(window),
    storage: browserStorage,
    timezone: () => Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC",
  });
  const capture = { draft, queue };
  // Only a browser tab keeps its stores; a server render reads nothing from them.
  if (typeof window !== "undefined") workspaces.set(ownerId, capture);
  return capture;
}

// Resolved on use, so a blocked browser storage API reaches the draft's and
// the queue's own error handling instead of failing while the workspace renders.
const browserStorage: QueueStorage = {
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
          "This Entry is in your Inbox, but one of its photos is invalid on this device, so they will not sync. Discard to remove them from this device.",
        status: "rejected",
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

      if (registered.status === "rejected") {
        return registered;
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
        message:
          "This Entry is in your Inbox, but one of its photos changed on this device, so they will not sync. Discard to remove them from this device.",
        status: "rejected",
      };
    }

    await client.storage.from("entry-media").upload(objectPath, photo.file, {
      cacheControl: "3600",
      contentType: attachment.mimeType,
      upsert: false,
    });

    const registered = await registerEntryAttachment(attachmentInput);

    if (registered.status !== "synced") {
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
