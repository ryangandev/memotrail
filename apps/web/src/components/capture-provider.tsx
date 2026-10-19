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
import { isAuthRetryableFetchError } from "@supabase/supabase-js";
import { notify } from "@/components/app-toast";
import { countLabel } from "@/lib/count-label";
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
import { synchronizeCapturePhotos } from "@/lib/data/inbox-photo-sync";
import {
  isInboxQueueStorageKey,
  loadInboxQueue,
  loadUnreadableCaptures,
  unreadableAttachmentIds,
  type QueueStorage,
  type QueuedInboxEntry,
} from "@/lib/data/inbox-queue";
import { createCaptureSyncRetry } from "@/lib/data/inbox-sync-retry";
import {
  countSyncedInQueueChange,
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
 * from any page, then keep retrying with backoff while the browser is online.
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
    // Retries belong to this signed-in workspace, so they end with it and never
    // send one person's captures under a later session.
    const retry = createCaptureSyncRetry({
      isOnline: () => navigator.onLine,
      isSyncing: () => queue.getSnapshot().isSyncing,
      retry: () => void queue.synchronize(),
    });
    // The sync Server Actions revalidate, so this tab's page already shows
    // what it synced and needs no refresh of its own.
    const stopWatchingRuns = queue.onRunFinished((run) => {
      retry.afterRun(run);
      const { rejected, result } = run;
      if (result?.status === "synced") notify.success(result.message);
      // A rejected capture may come from a composer that is already closed.
      if (rejected > 0)
        notify.error(
          `MemoTrail did not accept ${countLabel(rejected, "Entry")}. Review ${rejected === 1 ? "it" : "them"} in Pending sync.`,
        );
    });
    function handleOnline() {
      void queue.synchronize();
    }
    function handleOffline() {
      retry.stop();
    }
    function handleStorage(event: StorageEvent) {
      if (event.key === null || event.key === inboxDraftKey(ownerId))
        draft.reload();
      if (event.key !== null && !isInboxQueueStorageKey(event.key, ownerId))
        return;
      queue.reload();
      // A stored photo is a draft photo unless a queued capture holds it. The
      // photo announcement can arrive before this tab sees the new queue, so
      // the queue change rereads the draft photos too.
      void draft.reloadPhotos();
      // Another tab synced captures, so this page's Library is stale.
      if (countSyncedInQueueChange(event.oldValue, event.newValue) > 0)
        router.refresh();
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
    window.addEventListener("offline", handleOffline);
    window.addEventListener("pageshow", handlePageShow);
    window.addEventListener("storage", handleStorage);
    void draft.loadPhotos();
    if (navigator.onLine) void queue.synchronize();

    return () => {
      stopWatchingRuns();
      retry.stop();
      stopAnnouncingPhotos();
      photoChannel?.close();
      window.removeEventListener("online", handleOnline);
      window.removeEventListener("offline", handleOffline);
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
  Pick<
    InboxSyncStore,
    "discard" | "discardUnreadable" | "enqueue" | "getSnapshot" | "synchronize"
  >;

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
    discardUnreadable: queue.discardUnreadable,
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
    // An unreadable capture still owns its photos until it is discarded.
    queuedPhotoIds: () =>
      new Set([
        ...loadInboxQueue(browserStorage, ownerId).flatMap((entry) =>
          entry.attachments.map(({ id }) => id),
        ),
        ...loadUnreadableCaptures(browserStorage, ownerId).flatMap(
          ({ value }) => unreadableAttachmentIds(value),
        ),
      ]),
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

function synchronizeAttachments(
  ownerId: string,
  entry: QueuedInboxEntry,
  onProgress?: (progress: PhotoUploadProgress) => void,
): Promise<InboxSyncResult> {
  const media = () => createClient().storage.from("entry-media");
  return synchronizeCapturePhotos(
    ownerId,
    entry,
    {
      loadPhotos: () => loadInboxPhotoDrafts(ownerId),
      register: registerEntryAttachment,
      removePhoto: (attachmentId) =>
        removeInboxPhotoDrafts(ownerId, [attachmentId]),
      removeUpload: async (objectPath) => {
        await media().remove([objectPath]);
      },
      sessionFailure: async () => {
        const { data, error } = await createClient().auth.getUser();
        if (data.user?.id === ownerId) return null;
        // Only an answer from MemoTrail proves the session ended.
        return error &&
          (isAuthRetryableFetchError(error) || (error.status ?? 0) >= 500)
          ? "unavailable"
          : "session";
      },
      upload: (objectPath, photo) =>
        media().upload(objectPath, photo.file, {
          cacheControl: "3600",
          contentType: photo.mimeType,
          upsert: false,
        }),
    },
    onProgress,
  );
}
