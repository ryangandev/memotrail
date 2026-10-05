import type { InboxSyncRun } from "./inbox-sync";

/**
 * Waits before each automatic retry while the browser reports a connection,
 * growing so an unreachable MemoTrail is asked about once a minute at most.
 */
export const captureRetryDelays: readonly number[] = [
  1_000, 2_000, 4_000, 8_000, 15_000, 30_000, 60_000,
];

export type CaptureSyncRetry = {
  /** Schedules the next attempt when a finished run left a capture waiting. */
  afterRun: (run: InboxSyncRun) => void;
  /** Cancels a scheduled attempt and starts the next backoff from the beginning. */
  stop: () => void;
};

/**
 * Keeps retrying captures that are still waiting while the browser reports a
 * connection. The browser can announce `online` before requests get through,
 * and MemoTrail can be briefly unreachable while the connection stays up, so
 * a single failed attempt must not leave captures waiting until a reload.
 * Progress restarts the backoff; losing the connection stops it, since the
 * next `online` event starts a run of its own.
 */
export function createCaptureSyncRetry({
  delays = captureRetryDelays,
  isOnline,
  isSyncing,
  retry,
}: {
  delays?: readonly number[];
  isOnline: () => boolean;
  /** A run in progress schedules its own retry when it finishes. */
  isSyncing: () => boolean;
  retry: () => void;
}): CaptureSyncRetry {
  let timer: ReturnType<typeof setTimeout> | null = null;
  let step = 0;

  function cancel() {
    if (timer !== null) clearTimeout(timer);
    timer = null;
  }

  function stop() {
    cancel();
    step = 0;
  }

  return {
    afterRun(run) {
      cancel();
      if (run.result?.status !== "retry" || !isOnline()) {
        step = 0;
        return;
      }
      if (run.synced > 0 || run.rejected > 0) step = 0;
      const delay = delays[Math.min(step, delays.length - 1)];
      step += 1;
      timer = setTimeout(() => {
        timer = null;
        if (isOnline() && !isSyncing()) retry();
      }, delay);
    },
    stop,
  };
}
