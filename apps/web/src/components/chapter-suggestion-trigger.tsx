"use client";

import { useEffect } from "react";

/**
 * Asks, once per visit, whether a Chapter suggestion run is due. It renders nothing: the
 * database decides, and a suggestion appears on a later visit only if one was made.
 */
export function ChapterSuggestionTrigger() {
  useEffect(() => {
    void fetch("/api/chapter-suggestions", {
      cache: "no-store",
      method: "POST",
    }).catch(() => undefined);
  }, []);
  return null;
}
