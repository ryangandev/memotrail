"use client";

import { useSyncExternalStore } from "react";
import { Icon } from "@/components/icon";
import styles from "./workspace-shell.module.css";

const historyKey = "__memotrailHistoryId";
const storageKey = "memotrail-page-history-v1";
const listeners = new Set<() => void>();

type HistoryStack = { ids: string[]; index: number };
let stack: HistoryStack | null = null;
let uninstall: (() => void) | null = null;

function readId(state: unknown): string | null {
  if (!state || typeof state !== "object") return null;
  const id = (state as Record<string, unknown>)[historyKey];
  return typeof id === "string" ? id : null;
}

function withId(state: unknown, id: string): Record<string, unknown> {
  return {
    ...(state && typeof state === "object" ? state : {}),
    [historyKey]: id,
  };
}

function persist() {
  if (!stack) return;
  try {
    sessionStorage.setItem(storageKey, JSON.stringify(stack));
  } catch {
    // Navigation still works when storage is unavailable.
  }
  // Next can call pushState during React's insertion effect. Notify after that
  // phase so useSyncExternalStore never schedules a render from inside it.
  queueMicrotask(() => listeners.forEach((listener) => listener()));
}

function restore(): HistoryStack | null {
  try {
    const stored = JSON.parse(sessionStorage.getItem(storageKey) ?? "null");
    if (
      Array.isArray(stored?.ids) &&
      stored.ids.every((id: unknown) => typeof id === "string") &&
      Number.isInteger(stored.index) &&
      stored.index >= 0 &&
      stored.index < stored.ids.length
    ) {
      return stored as HistoryStack;
    }
  } catch {
    // Treat invalid or unavailable storage as a new navigation session.
  }
  return null;
}

function install() {
  const originalPush = history.pushState;
  const originalReplace = history.replaceState;
  const restored = restore();
  const currentId = readId(history.state);
  if (currentId && restored?.ids.includes(currentId)) {
    stack = { ids: restored.ids, index: restored.ids.indexOf(currentId) };
  } else {
    const id = currentId ?? crypto.randomUUID();
    stack = { ids: [id], index: 0 };
    originalReplace.call(history, withId(history.state, id), "");
  }
  persist();

  history.pushState = function (state, unused, url) {
    const id = crypto.randomUUID();
    originalPush.call(this, withId(state, id), unused, url);
    if (stack) {
      stack = {
        ids: [...stack.ids.slice(0, stack.index + 1), id],
        index: stack.index + 1,
      };
      persist();
    }
  };

  history.replaceState = function (state, unused, url) {
    const id = stack?.ids[stack.index] ?? crypto.randomUUID();
    originalReplace.call(this, withId(state, id), unused, url);
  };

  function syncCurrentEntry() {
    const id = readId(history.state);
    const index = id && stack ? stack.ids.indexOf(id) : -1;
    if (index >= 0 && stack) {
      stack = { ...stack, index };
    } else {
      const nextId = id ?? crypto.randomUUID();
      stack = { ids: [nextId], index: 0 };
      if (!id) originalReplace.call(history, withId(history.state, nextId), "");
    }
    persist();
  }

  window.addEventListener("popstate", syncCurrentEntry);
  window.addEventListener("pageshow", syncCurrentEntry);
  uninstall = () => {
    history.pushState = originalPush;
    history.replaceState = originalReplace;
    window.removeEventListener("popstate", syncCurrentEntry);
    window.removeEventListener("pageshow", syncCurrentEntry);
    uninstall = null;
    stack = null;
  };
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  if (!uninstall) install();
  return () => {
    listeners.delete(listener);
    if (listeners.size === 0) uninstall?.();
  };
}

function snapshot() {
  if (!stack) return 0;
  return (
    (stack.index > 0 ? 1 : 0) | (stack.index < stack.ids.length - 1 ? 2 : 0)
  );
}

export function WorkspaceHistoryControls() {
  const available = useSyncExternalStore(subscribe, snapshot, () => 0);

  return (
    <nav aria-label="Page history" className={styles.historyControls}>
      <button
        aria-label="Go back"
        className={styles.historyButton}
        disabled={(available & 1) === 0}
        onClick={() => history.back()}
        type="button"
      >
        <Icon name="arrowLeft" size={18} />
      </button>
      <button
        aria-label="Go forward"
        className={styles.historyButton}
        disabled={(available & 2) === 0}
        onClick={() => history.forward()}
        type="button"
      >
        <Icon name="arrowRight" size={18} />
      </button>
    </nav>
  );
}
