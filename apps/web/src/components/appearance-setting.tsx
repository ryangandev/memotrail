"use client";
import settingsFieldsStyles from "@/components/settings-fields.module.css";

import { useState } from "react";
import { saveThemePreference } from "@/app/settings/actions";
import { notify } from "@/components/app-toast";
import { Icon } from "@/components/icon";
import { themePreferences, type ThemePreference } from "@/lib/theme";

const labels: Record<ThemePreference, string> = {
  system: "System",
  light: "Light",
  dark: "Dark",
};

export function AppearanceSetting({
  initialPreference,
}: {
  initialPreference: ThemePreference;
}) {
  const [preference, setPreference] = useState(initialPreference);
  const [saved, setSaved] = useState(initialPreference);
  const [isPending, setIsPending] = useState(false);

  async function choose(next: ThemePreference) {
    show(next);
    setIsPending(true);
    try {
      await saveThemePreference(next);
      setSaved(next);
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
    <div className={settingsFieldsStyles.appearanceRow}>
      <span className={settingsFieldsStyles.preferenceIcon}>
        <Icon name="settings" size={20} />
      </span>
      <div>
        <strong>Appearance</strong>
        <p>Follow this device or choose a consistent light or dark theme.</p>
      </div>
      <fieldset
        aria-busy={isPending}
        className={settingsFieldsStyles.appearanceControl}
        disabled={isPending}
      >
        <legend>Appearance mode</legend>
        {themePreferences.map((option) => (
          <label key={option}>
            <input
              checked={preference === option}
              name="appearance"
              onChange={() => void choose(option)}
              type="radio"
              value={option}
            />
            <span>{labels[option]}</span>
          </label>
        ))}
      </fieldset>
    </div>
  );
}
