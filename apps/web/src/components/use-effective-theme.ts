"use client";

import { useSyncExternalStore } from "react";

export type EffectiveTheme = "light" | "dark";

const darkModeQuery = "(prefers-color-scheme: dark)";

function currentTheme(): EffectiveTheme {
  const explicit = document.documentElement.getAttribute("data-theme");
  if (explicit === "light" || explicit === "dark") return explicit;
  return window.matchMedia(darkModeQuery).matches ? "dark" : "light";
}

function subscribe(onChange: () => void) {
  const media = window.matchMedia(darkModeQuery);
  const observer = new MutationObserver(onChange);
  observer.observe(document.documentElement, {
    attributes: true,
    attributeFilter: ["data-theme"],
  });
  media.addEventListener("change", onChange);
  return () => {
    observer.disconnect();
    media.removeEventListener("change", onChange);
  };
}

export function useEffectiveTheme(): EffectiveTheme | null {
  return useSyncExternalStore(subscribe, currentTheme, () => null);
}
