"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { homeTimezoneCookieName } from "@/lib/data/home-input";

export function TimezoneSync() {
  const router = useRouter();

  useEffect(() => {
    const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone;

    if (!timezone) {
      return;
    }

    const currentTimezone = document.cookie
      .split(";")
      .map((item) => item.trim().split("="))
      .find(([name]) => name === homeTimezoneCookieName)?.[1];

    if (currentTimezone) {
      try {
        if (decodeURIComponent(currentTimezone) === timezone) {
          return;
        }
      } catch {
        // Replace malformed client state with the browser's current timezone.
      }
    }

    const secure = window.location.protocol === "https:" ? "; Secure" : "";
    document.cookie = `${homeTimezoneCookieName}=${encodeURIComponent(timezone)}; Path=/; Max-Age=31536000; SameSite=Lax${secure}`;
    router.refresh();
  }, [router]);

  return null;
}
