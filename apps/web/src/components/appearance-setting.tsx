"use client";
import settingsFieldsStyles from "@/components/settings-fields.module.css";

import { useState, useTransition } from "react";
import { saveThemePreference } from "@/app/settings/actions";

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
  const [isPending, startTransition] = useTransition();

  function choose(next: ThemePreference) {
    setPreference(next);
    if (next === "system") {
      document.documentElement.removeAttribute("data-theme");
    } else {
      document.documentElement.setAttribute("data-theme", next);
    }
    startTransition(async () => {
      await saveThemePreference(next);
    });
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
              onChange={() => choose(option)}
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
