"use client";

import { createContext, useContext, type RefObject } from "react";

// Nested popovers stay inside a modal's accessibility and theme boundary.
export const OverlayContainerContext = createContext<
  RefObject<HTMLElement | null> | undefined
>(undefined);
export function useOverlayContainer() {
  return useContext(OverlayContainerContext);
}
