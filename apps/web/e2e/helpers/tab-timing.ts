import type { Page } from "@playwright/test";

/**
 * Makes a tab hear of other tabs late, as a busy machine can: its storage
 * events, and optionally its own reconnection, reach the page only after a
 * delay. With `staleQueue`, the tab also keeps reading the pending capture
 * queue it last saw until the storage event arrives, as when another tab's
 * write has not yet reached this tab's copy of localStorage. Call it before
 * the tab loads.
 */
export async function hearOtherTabsLate(
  page: Page,
  {
    onlineMs = 0,
    staleQueue = false,
    storageMs,
  }: { onlineMs?: number; staleQueue?: boolean; storageMs: number },
) {
  await page.addInitScript(
    ({ onlineMs, staleQueue, storageMs }) => {
      const lags = (key: string | null) =>
        staleQueue && (key?.startsWith("memotrail:inbox-queue:") ?? false);
      const seen = new Map<string, string | null>();
      const getItem = Storage.prototype.getItem;
      const setItem = Storage.prototype.setItem;
      Storage.prototype.getItem = function (key: string) {
        if (!lags(key)) return getItem.call(this, key);
        if (!seen.has(key)) seen.set(key, getItem.call(this, key));
        return seen.get(key) ?? null;
      };
      Storage.prototype.setItem = function (key: string, value: string) {
        if (lags(key)) seen.set(key, value);
        setItem.call(this, key, value);
      };
      const addEventListener = window.addEventListener;
      window.addEventListener = function (
        this: Window,
        type: string,
        listener: EventListenerOrEventListenerObject,
        options?: boolean | AddEventListenerOptions,
      ) {
        const delay =
          type === "storage" ? storageMs : type === "online" ? onlineMs : 0;
        if (!delay || typeof listener !== "function")
          return addEventListener.call(this, type, listener, options);
        return addEventListener.call(
          this,
          type,
          (event: Event) =>
            setTimeout(() => {
              if (event instanceof StorageEvent && event.key && lags(event.key))
                seen.set(event.key, event.newValue);
              listener.call(window, event);
            }, delay),
          options,
        );
      } as typeof window.addEventListener;
    },
    { onlineMs, staleQueue, storageMs },
  );
}
