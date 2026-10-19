"use client";

import { useId, useState } from "react";
import { saveThemePreference } from "@/app/settings/actions";
import { notify } from "@/components/app-toast";
import { SegmentedControl } from "@/components/segmented-control";
import { SettingRow } from "@/components/setting-row";
import { themePreferences, type ThemePreference } from "@/lib/theme";

const labels: Record<ThemePreference, string> = {
  system: "System",
  light: "Light",
  dark: "Dark",
};

const options = themePreferences.map((value) => ({
  label: labels[value],
  value,
}));

export function AppearanceSetting({
  initialPreference,
}: {
  initialPreference: ThemePreference;
}) {
  const id = useId();
  const [preference, setPreference] = useState(initialPreference);
  const [saved, setSaved] = useState(initialPreference);
  const [isPending, setIsPending] = useState(false);
  const [confirmed, setConfirmed] = useState(false);

  async function choose(next: ThemePreference) {
    show(next);
    setConfirmed(false);
    setIsPending(true);
    try {
      await saveThemePreference(next);
      setSaved(next);
      setConfirmed(true);
    } catch {
      // The choice never reached MemoTrail, so the page goes back to the one
      // that is saved rather than showing a theme the next visit will not keep.
      show(saved);
      notify.error(
        "Appearance could not be saved. Check your connection and try again.",
      );
    } finally {
      setIsPending(false);
    }
  }

  function show(next: ThemePreference) {
    setPreference(next);
    if (next === "system") {
      document.documentElement.removeAttribute("data-theme");
    } else {
      document.documentElement.setAttribute("data-theme", next);
    }
  }

  return (
    <SettingRow
      help="System follows this device. Light and Dark stay the same everywhere."
      id={id}
      label="Theme"
      saved={confirmed}
    >
      <SegmentedControl
        disabled={isPending}
        label="Theme"
        name="appearance"
        onChange={(next) => void choose(next)}
        options={options}
        value={preference}
      />
    </SettingRow>
  );
}
