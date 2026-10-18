"use client";

import { useCallback } from "react";

/**
 * The open native modal dialog an overlay must render inside, such as Quick
 * Capture. The browser shows that dialog in the top layer and makes everything
 * outside it inert, so an overlay portaled to `document.body` would sit under
 * it and could not take focus or clicks. MemoTrail opens at most one native
 * modal dialog, so the last in document order is the topmost.
 */
export function topmostModalDialog() {
  if (typeof document === "undefined") return null;
  const dialogs = document.querySelectorAll<HTMLDialogElement>("dialog:modal");
  return dialogs.item(dialogs.length - 1);
}

/**
 * A ref that shows its `popover="manual"` element in the top layer from the
 * moment it mounts until it unmounts, above everything shown there before it,
 * so a scrolling, filtered, or translucent ancestor cannot clip it. The element
 * stays in its container's tree, so it keeps that container's theme and focus
 * scope, and a native modal dialog around it does not make it inert.
 */
export function useTopLayerRef<T extends HTMLElement>(active: boolean) {
  return useCallback(
    (element: T | null) => {
      if (!active || !element || typeof element.showPopover !== "function")
        return;
      if (!element.matches(":popover-open")) element.showPopover();
      return () => {
        if (element.isConnected && element.matches(":popover-open"))
          element.hidePopover();
      };
    },
    [active],
  );
}
