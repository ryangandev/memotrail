import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { InboxSyncRun } from "./inbox-sync";
import { captureRetryDelays, createCaptureSyncRetry } from "./inbox-sync-retry";

const waiting: InboxSyncRun = {
  rejected: 0,
  result: { message: "Saved on this device.", status: "retry" },
  synced: 0,
};

describe("Automatic capture sync retries", () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("retries a waiting capture with growing delays while online", () => {
    const { retry, scheduler } = setup();

    for (const delay of [1_000, 2_000, 4_000]) {
      scheduler.afterRun(waiting);
      vi.advanceTimersByTime(delay - 1);
      expect(retry).not.toHaveBeenCalled();
      vi.advanceTimersByTime(1);
      expect(retry).toHaveBeenCalledOnce();
      retry.mockClear();
    }
  });

  it("asks an unreachable MemoTrail once a minute at most", () => {
    const { retry, scheduler } = setup();

    for (const delay of captureRetryDelays) {
      scheduler.afterRun(waiting);
      vi.advanceTimersByTime(delay);
    }
    retry.mockClear();
    scheduler.afterRun(waiting);
    vi.advanceTimersByTime(59_999);
    expect(retry).not.toHaveBeenCalled();
    vi.advanceTimersByTime(1);
    expect(retry).toHaveBeenCalledOnce();
  });

  it("restarts the backoff after a run makes progress", () => {
    const { retry, scheduler } = setup();
    scheduler.afterRun(waiting);
    vi.advanceTimersByTime(1_000);
    scheduler.afterRun(waiting);
    vi.advanceTimersByTime(2_000);
    retry.mockClear();

    // One capture synced and a later one must still wait.
    scheduler.afterRun({ ...waiting, synced: 1 });
    vi.advanceTimersByTime(1_000);
    expect(retry).toHaveBeenCalledOnce();
  });

  it("stops when nothing waits, and starts over for the next failure", () => {
    const { retry, scheduler } = setup();
    scheduler.afterRun(waiting);
    vi.advanceTimersByTime(1_000);
    scheduler.afterRun(waiting);

    scheduler.afterRun({
      rejected: 0,
      result: { message: "Saved to Library.", status: "synced" },
      synced: 1,
    });
    retry.mockClear();
    vi.advanceTimersByTime(60_000);
    expect(retry).not.toHaveBeenCalled();

    scheduler.afterRun(waiting);
    vi.advanceTimersByTime(1_000);
    expect(retry).toHaveBeenCalledOnce();
  });

  it("leaves offline captures to the browser's next online event", () => {
    const { online, retry, scheduler } = setup();
    online.value = false;
    scheduler.afterRun(waiting);
    vi.advanceTimersByTime(60_000);
    expect(retry).not.toHaveBeenCalled();

    // A retry scheduled before the connection dropped does not run offline.
    online.value = true;
    scheduler.afterRun(waiting);
    online.value = false;
    vi.advanceTimersByTime(60_000);
    expect(retry).not.toHaveBeenCalled();
  });

  it("does not start a second run while one is in progress", () => {
    const { retry, scheduler, syncing } = setup();
    scheduler.afterRun(waiting);
    syncing.value = true;
    vi.advanceTimersByTime(1_000);
    expect(retry).not.toHaveBeenCalled();
  });

  it("cancels a scheduled retry and its backoff when stopped", () => {
    const { retry, scheduler } = setup();
    scheduler.afterRun(waiting);
    vi.advanceTimersByTime(1_000);
    scheduler.afterRun(waiting);
    scheduler.stop();
    vi.advanceTimersByTime(60_000);
    expect(retry).toHaveBeenCalledOnce();

    retry.mockClear();
    scheduler.afterRun(waiting);
    vi.advanceTimersByTime(1_000);
    expect(retry).toHaveBeenCalledOnce();
  });
});

function setup() {
  const online = { value: true };
  const syncing = { value: false };
  const retry = vi.fn();
  const scheduler = createCaptureSyncRetry({
    isOnline: () => online.value,
    isSyncing: () => syncing.value,
    retry,
  });
  return { online, retry, scheduler, syncing };
}
